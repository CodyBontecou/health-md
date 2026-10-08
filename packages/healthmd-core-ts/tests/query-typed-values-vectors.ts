/** Stage1 contract only; source/test implementation and execution require independent clearance. */
import type * as Effect from "effect/Effect";
import type * as Result from "effect/Result";
import type * as Scope from "effect/Scope";
declare const typedBrand: unique symbol, readBrand: unique symbol, nativeBrand: unique symbol;
export interface OwnedTypedValue { readonly [typedBrand]: true }
export interface OwnedReadRequest { readonly [readBrand]: true }
export interface OwnedNativeScalar { readonly [nativeBrand]: true }
export interface FixedTypedFailure { readonly _tag:"TypedValueFailure"; readonly code:"invalid_typed_value"|"private_value_limit"|"native_profile_unavailable"|"non_finite_number"|"not_authorized"|"owned_handoff_closed"|"private_value_busy" }
export type UnknownJson = {readonly kind:"null"}|{readonly kind:"boolean";readonly value:boolean}|{readonly kind:"string";readonly value:string}|{readonly kind:"i64"|"u64";readonly decimal:string}|{readonly kind:"f64";readonly bits:string}|{readonly kind:"array";readonly values:readonly UnknownJson[]}|{readonly kind:"object";readonly entries:readonly (readonly [string,UnknownJson])[]};
export type TypedView = {readonly type:"quantity";readonly bits:string;readonly unit:string}|{readonly type:"duration";readonly bits:string;readonly unit:"s"}|{readonly type:"count";readonly decimal:string;readonly unit:"count"}|{readonly type:"string"|"date";readonly value:string}|{readonly type:"boolean";readonly value:boolean}|{readonly type:"category";readonly identifier:string;readonly display:string|null;readonly raw_value:string|null}|{readonly type:"timestamp";readonly native_profile:"foundation_Date_reproduce_bytes";readonly canonical:string;readonly exact_unix_nanoseconds_claimed:false;readonly reference_bits?:string;readonly unix_bits?:string}|{readonly type:"array";readonly values:readonly TypedView[]}|{readonly type:"unknown";readonly tag:string;readonly value:UnknownJson|null};
export type TypedPhase="before_decode"|"after_profile"|"before_read"|"before_encode"|"before_publication"|"after_callback";
export interface CapturedTypedCurrent { check(phase:TypedPhase):Effect.Effect<void,FixedTypedFailure> }
/** Closed trusted timestamp operand; optional bit operands are independent source observations, never derived from canonical text. */
export interface NativeTimestampInput { readonly canonical:string; readonly reference_bits?:string; readonly unix_bits?:string }
export interface NativeScalarIssuer {
 issueNumber(slot:unknown,kind:"i64"|"u64"|"f64",payload:unknown):OwnedNativeScalar|null;
 issueTimestamp(slot:unknown,canonical:unknown,reference_bits?:unknown,unix_bits?:unknown):OwnedNativeScalar|null;
}
/** Trusted profile capability, captured once. Issuance authenticates callback/factory/frame/slot only; it is not source authorization. */
export interface NativeTypedProfile {
 number(rawToken: string, context:"i64_count"|"i64_category"|"quantity_f64"|"duration_f64"|"unknown_JSON",slot:unknown,issuer:NativeScalarIssuer):Effect.Effect<OwnedNativeScalar,FixedTypedFailure>;
 timestamp(rawCanonical:string,slot:unknown,issuer:NativeScalarIssuer):Effect.Effect<OwnedNativeScalar,FixedTypedFailure>;
 canonicalNumber(kind:"i64"|"u64"|"f64",payload:string):Result.Result<string,FixedTypedFailure>;
 duplicateDecodedKey(rawFrame:string,key:string):Result.Result<"first"|"last"|"reject",FixedTypedFailure>;
}
export interface TypedReadView { read(request:unknown,value:unknown):Effect.Effect<TypedView|null,FixedTypedFailure>; encode(request:unknown,value:unknown):Effect.Effect<string|null,FixedTypedFailure> }
export interface TypedValueFactory {
 decode(representation:unknown,payload:unknown):Effect.Effect<OwnedTypedValue,FixedTypedFailure>;
 withValue<A,E>(value:unknown,callback:(request:OwnedReadRequest,view:TypedReadView)=>Effect.Effect<A,E>):Effect.Effect<A,E|FixedTypedFailure>;
}
export declare function createTypedValueFactory(current:CapturedTypedCurrent,native:NativeTypedProfile):Effect.Effect<TypedValueFactory,FixedTypedFailure,Scope.Scope>;

export const queryTypedValuesFixture = {
  "schema_version": 1,
  "task_id": "QUERY-TYPED-VALUES",
  "assigned_source": "32f38da439c0489648e99933c99d88805b76ca7b",
  "status": "Stage1_frozen_pending_independent_review",
  "proof_class": "portable_synthetic",
  "source_pins": [
    {
      "path": "AGENTS.md",
      "current_sha256": "830901de59e2afe2023a35bddaa6a1b620d8b40f14bad33d9675ccdadda75f0d",
      "current_bytes": 6509,
      "assigned_Git_sha256": "830901de59e2afe2023a35bddaa6a1b620d8b40f14bad33d9675ccdadda75f0d",
      "assigned_Git_bytes": 6509,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/AGENTS.md",
      "current_sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
      "current_bytes": 860,
      "assigned_Git_sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
      "assigned_Git_bytes": 860,
      "current_equals_assigned": true
    },
    {
      "path": "GLOSSARY.md",
      "current_sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
      "current_bytes": 3868,
      "assigned_Git_sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
      "assigned_Git_bytes": 3868,
      "current_equals_assigned": true
    },
    {
      "path": "docs/architecture/javascript-unified-layer-research.md",
      "current_sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
      "current_bytes": 13361,
      "assigned_Git_sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
      "assigned_Git_bytes": 13361,
      "current_equals_assigned": true
    },
    {
      "path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "current_sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd",
      "current_bytes": 284562,
      "assigned_Git_sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd",
      "assigned_Git_bytes": 284562,
      "current_equals_assigned": true
    },
    {
      "path": "docs/architecture/cross-platform-unification-policy.md",
      "current_sha256": "49a35d47c37bd721c9d2a83607a3a4bdc7c82a26a7ceae160f5208bd577b95fc",
      "current_bytes": 9482,
      "assigned_Git_sha256": "49a35d47c37bd721c9d2a83607a3a4bdc7c82a26a7ceae160f5208bd577b95fc",
      "assigned_Git_bytes": 9482,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/core-cli.md",
      "current_sha256": "4b33f46482c9c3fe26b50badc07a0a604e5c97345cb7f5eb6526580ced249749",
      "current_bytes": 5578,
      "assigned_Git_sha256": "4b33f46482c9c3fe26b50badc07a0a604e5c97345cb7f5eb6526580ced249749",
      "assigned_Git_bytes": 5578,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/personal-data.md",
      "current_sha256": "0f532bf08cbbf2e704bb39c85269874c0299dd9bfcf54ee5e21ba726dde98ea0",
      "current_bytes": 5582,
      "assigned_Git_sha256": "0f532bf08cbbf2e704bb39c85269874c0299dd9bfcf54ee5e21ba726dde98ea0",
      "assigned_Git_bytes": 5582,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/templates.md",
      "current_sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
      "current_bytes": 10054,
      "assigned_Git_sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
      "assigned_Git_bytes": 10054,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "current_sha256": "d013adcb657d2b190a75506ddef1adc85a3181c4eb3cf5180a8834789961fbe3",
      "current_bytes": 347600,
      "assigned_Git_sha256": "d013adcb657d2b190a75506ddef1adc85a3181c4eb3cf5180a8834789961fbe3",
      "assigned_Git_bytes": 347600,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/core.json",
      "current_sha256": "56536fc5f207a1f8508542ca98fd7d01cff3b882db002a3df8521bdb59d39ac7",
      "current_bytes": 95633,
      "assigned_Git_sha256": "56536fc5f207a1f8508542ca98fd7d01cff3b882db002a3df8521bdb59d39ac7",
      "assigned_Git_bytes": 95633,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/donors.json",
      "current_sha256": "67b9dbc945c6e292e7cba25502e3afc43dcb9a35f4ba797b08124d044ef9e54d",
      "current_bytes": 240223,
      "assigned_Git_sha256": "67b9dbc945c6e292e7cba25502e3afc43dcb9a35f4ba797b08124d044ef9e54d",
      "assigned_Git_bytes": 240223,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-CLI.json",
      "current_sha256": "be25457e7c1672dfacc706702a47c762e3bb9781ecb978391412195247d824f1",
      "current_bytes": 12304,
      "assigned_Git_sha256": "be25457e7c1672dfacc706702a47c762e3bb9781ecb978391412195247d824f1",
      "assigned_Git_bytes": 12304,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-CORE.json",
      "current_sha256": "839b110fc881fdbf73d2bb9f06b6bab3f35c74eaf0f7c6f3d8d63d8b42c19c9a",
      "current_bytes": 26431,
      "assigned_Git_sha256": "839b110fc881fdbf73d2bb9f06b6bab3f35c74eaf0f7c6f3d8d63d8b42c19c9a",
      "assigned_Git_bytes": 26431,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/SLICE-PARITY.json",
      "current_sha256": "c8f395b086606b685c3f539d105a74036a4f42608534a1eb80d11c2ecf67a4f4",
      "current_bytes": 27886,
      "assigned_Git_sha256": "c8f395b086606b685c3f539d105a74036a4f42608534a1eb80d11c2ecf67a4f4",
      "assigned_Git_bytes": 27886,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/QUERY-TRAVERSAL.json",
      "current_sha256": "d78dcac7a562180f9a30ec4459b0bde53c7e7080cddcf44f6d2edd27d3a2b87d",
      "current_bytes": 22328,
      "assigned_Git_sha256": "d78dcac7a562180f9a30ec4459b0bde53c7e7080cddcf44f6d2edd27d3a2b87d",
      "assigned_Git_bytes": 22328,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/cohorts/core-ts-ios-eligibility-v1.json",
      "current_sha256": "25b48beb5c7cd641d3161b3b362accdabf04bc0a5118042209651e88e18fe761",
      "current_bytes": 47904,
      "assigned_Git_sha256": "25b48beb5c7cd641d3161b3b362accdabf04bc0a5118042209651e88e18fe761",
      "assigned_Git_bytes": 47904,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CORE-COHORT-IOS-ELIGIBILITY.json",
      "current_sha256": "2aeb43dc54043fef42e8f2ace7ddafb46c915d54b659034e2b1fc74143f207c0",
      "current_bytes": 171341,
      "assigned_Git_sha256": "2aeb43dc54043fef42e8f2ace7ddafb46c915d54b659034e2b1fc74143f207c0",
      "assigned_Git_bytes": 171341,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-REVIEW.json",
      "current_sha256": "9c1f44fd63b564fe9a5d0ee6eaeff2a22f34615b1abfd59d8efe23bd4154b4ae",
      "current_bytes": 18284,
      "assigned_Git_sha256": "9c1f44fd63b564fe9a5d0ee6eaeff2a22f34615b1abfd59d8efe23bd4154b4ae",
      "assigned_Git_bytes": 18284,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "current_sha256": "856276a9a184d466ead3c7e9c6c865e782ec830562cbf31e68a3d2d3dfd9775c",
      "current_bytes": 68436,
      "assigned_Git_sha256": "856276a9a184d466ead3c7e9c6c865e782ec830562cbf31e68a3d2d3dfd9775c",
      "assigned_Git_bytes": 68436,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "current_sha256": "1b63355846d9a5637ee723f8199b0bf7774a601479e0092ed52ca9b8fdf606df",
      "current_bytes": 34193,
      "assigned_Git_sha256": "1b63355846d9a5637ee723f8199b0bf7774a601479e0092ed52ca9b8fdf606df",
      "assigned_Git_bytes": 34193,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/package.json",
      "current_sha256": "0a3d08770c6147b15dc0d56f3ff29888d7ce3822d0ba0879f0a1f494e9378bc0",
      "current_bytes": 1553,
      "assigned_Git_sha256": "0a3d08770c6147b15dc0d56f3ff29888d7ce3822d0ba0879f0a1f494e9378bc0",
      "assigned_Git_bytes": 1553,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/package-lock.json",
      "current_sha256": "61746468956308b8a7811cc02fb41c6ac239d5830121ceffeab43324b639c36e",
      "current_bytes": 27929,
      "assigned_Git_sha256": "61746468956308b8a7811cc02fb41c6ac239d5830121ceffeab43324b639c36e",
      "assigned_Git_bytes": 27929,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/.node-version",
      "current_sha256": "73fb1b615e2043a933be1c0895cde4358036acc28d785692509b822aa53c761f",
      "current_bytes": 8,
      "assigned_Git_sha256": "73fb1b615e2043a933be1c0895cde4358036acc28d785692509b822aa53c761f",
      "assigned_Git_bytes": 8,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/scripts/check.mjs",
      "current_sha256": "e61622b1190322a61021055b342636e5edfd7f4cfba7ef7e240e375a7a6c3eae",
      "current_bytes": 2766,
      "assigned_Git_sha256": "e61622b1190322a61021055b342636e5edfd7f4cfba7ef7e240e375a7a6c3eae",
      "assigned_Git_bytes": 2766,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/scripts/check-boundaries.mjs",
      "current_sha256": "3493efc125aede6d9132061ea8e23383928e1c9389109af4b92eb5097abb5f09",
      "current_bytes": 8065,
      "assigned_Git_sha256": "3493efc125aede6d9132061ea8e23383928e1c9389109af4b92eb5097abb5f09",
      "assigned_Git_bytes": 8065,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/crates/healthmd-operations/src/registry.rs",
      "current_sha256": "0d16820bf891bd5ac71741f7ac955887c3be289201a01893100f1886f3a2a827",
      "current_bytes": 52174,
      "assigned_Git_sha256": "0d16820bf891bd5ac71741f7ac955887c3be289201a01893100f1886f3a2a827",
      "assigned_Git_bytes": 52174,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/crates/healthmd-operations/src/normalize.rs",
      "current_sha256": "ab026b1d0e991bc2c79f8c02b2b8348241bcbfc9195474d46fc9d22bd6aefd54",
      "current_bytes": 42321,
      "assigned_Git_sha256": "ab026b1d0e991bc2c79f8c02b2b8348241bcbfc9195474d46fc9d22bd6aefd54",
      "assigned_Git_bytes": 42321,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/crates/healthmd-operations/src/backend.rs",
      "current_sha256": "733d0e8ed94b17347a3308757d2da314c96fda1a88d0f9fa83350583b19e2845",
      "current_bytes": 7487,
      "assigned_Git_sha256": "733d0e8ed94b17347a3308757d2da314c96fda1a88d0f9fa83350583b19e2845",
      "assigned_Git_bytes": 7487,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/crates/healthmd-operations/src/model.rs",
      "current_sha256": "a60a1163ab5861ce062d010045e2e6bad8f1c6fccbea2094ead3f0c0980850ad",
      "current_bytes": 1129,
      "assigned_Git_sha256": "a60a1163ab5861ce062d010045e2e6bad8f1c6fccbea2094ead3f0c0980850ad",
      "assigned_Git_bytes": 1129,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/crates/healthmd-operations/src/service.rs",
      "current_sha256": "0104127cfdf159d43eff42296d693a12bdaf2265dfe6039eeeddd2af8444191c",
      "current_bytes": 6172,
      "assigned_Git_sha256": "0104127cfdf159d43eff42296d693a12bdaf2265dfe6039eeeddd2af8444191c",
      "assigned_Git_bytes": 6172,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/crates/healthmd-operations/src/limits.rs",
      "current_sha256": "2a5f0ea3854fdb54550a1e075195407141321cc2cc1edeb91c05a3f047485184",
      "current_bytes": 1376,
      "assigned_Git_sha256": "2a5f0ea3854fdb54550a1e075195407141321cc2cc1edeb91c05a3f047485184",
      "assigned_Git_bytes": 1376,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/application.rs",
      "current_sha256": "989bfd02c8c243237628343cf4500a07cce3731facb00565735ef35863657d8a",
      "current_bytes": 58209,
      "assigned_Git_sha256": "989bfd02c8c243237628343cf4500a07cce3731facb00565735ef35863657d8a",
      "assigned_Git_bytes": 58209,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/Cargo.toml",
      "current_sha256": "55c7b45a78c3c87918d93fce970196f50468e616e85583f8eeb283f14bc3d90d",
      "current_bytes": 2646,
      "assigned_Git_sha256": "55c7b45a78c3c87918d93fce970196f50468e616e85583f8eeb283f14bc3d90d",
      "assigned_Git_bytes": 2646,
      "current_equals_assigned": true
    },
    {
      "path": "apps/cli/Cargo.lock",
      "current_sha256": "2ceea3ac125f41d6d89230af204dc619152a0b657cbcefe6d1ce817fbc213bd5",
      "current_bytes": 88843,
      "assigned_Git_sha256": "2ceea3ac125f41d6d89230af204dc619152a0b657cbcefe6d1ce817fbc213bd5",
      "assigned_Git_bytes": 88843,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-rust/Cargo.toml",
      "current_sha256": "5efe86a7ad3b643e2415a11f6f2c4f530e82ccb2a3e5094897e64846b1d5b61f",
      "current_bytes": 2018,
      "assigned_Git_sha256": "5efe86a7ad3b643e2415a11f6f2c4f530e82ccb2a3e5094897e64846b1d5b61f",
      "assigned_Git_bytes": 2018,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-rust/Cargo.lock",
      "current_sha256": "fdbc69316d3556d8a2483d4821267a93ddfd8861acba3be1c850aabdcefada4b",
      "current_bytes": 36294,
      "assigned_Git_sha256": "fdbc69316d3556d8a2483d4821267a93ddfd8861acba3be1c850aabdcefada4b",
      "assigned_Git_bytes": 36294,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/Shared/Query/QueryContracts.swift",
      "current_sha256": "72f56754e04653b9262394932b9baaac0468cc96a8b498dd11c35be989f00118",
      "current_bytes": 54211,
      "assigned_Git_sha256": "72f56754e04653b9262394932b9baaac0468cc96a8b498dd11c35be989f00118",
      "assigned_Git_bytes": 54211,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/Shared/Query/QueryTypedValue.swift",
      "current_sha256": "1658be7cf1db8ad530356eebf2e986a501ef223f57ffc2571a9540817e57916f",
      "current_bytes": 8432,
      "assigned_Git_sha256": "1658be7cf1db8ad530356eebf2e986a501ef223f57ffc2571a9540817e57916f",
      "assigned_Git_bytes": 8432,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/Shared/Query/QueryCanonicalSerializer.swift",
      "current_sha256": "b6b2de86e7cfd0c03c7105ae65750b23189ab7f163e4823ee4d983bcc0445feb",
      "current_bytes": 6998,
      "assigned_Git_sha256": "b6b2de86e7cfd0c03c7105ae65750b23189ab7f163e4823ee4d983bcc0445feb",
      "assigned_Git_bytes": 6998,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift",
      "current_sha256": "54b13797c7f94170aae77d33bd89a27fdb8a9b3e6c03fce796df2eefd01141ee",
      "current_bytes": 60997,
      "assigned_Git_sha256": "54b13797c7f94170aae77d33bd89a27fdb8a9b3e6c03fce796df2eefd01141ee",
      "assigned_Git_bytes": 60997,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/Shared/Query/HealthMdQueryContextProjector.swift",
      "current_sha256": "2e4de29fd916b7b313f6c3c9840ff1cee6dce1460186db2891282401b00eb79f",
      "current_bytes": 45870,
      "assigned_Git_sha256": "2e4de29fd916b7b313f6c3c9840ff1cee6dce1460186db2891282401b00eb79f",
      "assigned_Git_bytes": 45870,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/Shared/Query/HealthMdSleepSessionQuery.swift",
      "current_sha256": "d87ad3432c4c8d23ee6760fae56cca57d8d7992c3eeaff04792853d2a6ef62eb",
      "current_bytes": 25564,
      "assigned_Git_sha256": "d87ad3432c4c8d23ee6760fae56cca57d8d7992c3eeaff04792853d2a6ef62eb",
      "assigned_Git_bytes": 25564,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift",
      "current_sha256": "8a69809edf797dae23af3b7e30af3e50c51e43a2de53febcadf4646a6931e2f7",
      "current_bytes": 42303,
      "assigned_Git_sha256": "8a69809edf797dae23af3b7e30af3e50c51e43a2de53febcadf4646a6931e2f7",
      "assigned_Git_bytes": 42303,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/iOS/IPhoneDirectQueryCoordinator.swift",
      "current_sha256": "c8853d6146182271df6a36c6f69144e60351f6b0149fc726819d82f5a97e9655",
      "current_bytes": 23373,
      "assigned_Git_sha256": "c8853d6146182271df6a36c6f69144e60351f6b0149fc726819d82f5a97e9655",
      "assigned_Git_bytes": 23373,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMd/macOS/Managers/EncryptedHealthContextQueryExecutor.swift",
      "current_sha256": "4ed7a29568a34952760ac7bb81ade5034b2230ae89dd2845bb1ca30f8944ce68",
      "current_bytes": 109333,
      "assigned_Git_sha256": "4ed7a29568a34952760ac7bb81ade5034b2230ae89dd2845bb1ca30f8944ce68",
      "assigned_Git_bytes": 109333,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "current_sha256": "233bd08c54357afcecc74091bae37a68b5fd6e32818e34b09777273ac621d1af",
      "current_bytes": 44578,
      "assigned_Git_sha256": "233bd08c54357afcecc74091bae37a68b5fd6e32818e34b09777273ac621d1af",
      "assigned_Git_bytes": 44578,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
      "current_sha256": "2f6f584624d0d75077f466cbffcb3d7c03229db2bc342908d8b721f0b930f23b",
      "current_bytes": 24546,
      "assigned_Git_sha256": "2f6f584624d0d75077f466cbffcb3d7c03229db2bc342908d8b721f0b930f23b",
      "assigned_Git_bytes": 24546,
      "current_equals_assigned": true
    },
    {
      "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
      "current_sha256": "3ab89bbfd7f211a748e15ab09a610939809cbf526babbb62ee33cd0ea5b9fe8b",
      "current_bytes": 35211,
      "assigned_Git_sha256": "3ab89bbfd7f211a748e15ab09a610939809cbf526babbb62ee33cd0ea5b9fe8b",
      "assigned_Git_bytes": 35211,
      "current_equals_assigned": true
    },
    {
      "path": "apps/android/direct-protocol/src/main/kotlin/com/healthmd/direct/protocol/ProtocolModels.kt",
      "current_sha256": "082ade5953c87e0ce17c1da2722612d4f37010c63eaafb76d3d628c1fe0b8b5f",
      "current_bytes": 15238,
      "assigned_Git_sha256": "082ade5953c87e0ce17c1da2722612d4f37010c63eaafb76d3d628c1fe0b8b5f",
      "assigned_Git_bytes": 15238,
      "current_equals_assigned": true
    },
    {
      "path": "apps/android/direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/InteroperabilityTest.kt",
      "current_sha256": "fa082aad6433140fcd5ee461f287202de685a6bafb75ebf3f2298bca9b975f08",
      "current_bytes": 7782,
      "assigned_Git_sha256": "fa082aad6433140fcd5ee461f287202de685a6bafb75ebf3f2298bca9b975f08",
      "assigned_Git_bytes": 7782,
      "current_equals_assigned": true
    },
    {
      "path": "packages/contracts/direct-protocol/v1/fixtures/swift-reference.json",
      "current_sha256": "372655a8a415b5256b86ef628f551515bc66440eae8412d28be0dd7dfbe0f4a1",
      "current_bytes": 2164,
      "assigned_Git_sha256": "372655a8a415b5256b86ef628f551515bc66440eae8412d28be0dd7dfbe0f4a1",
      "assigned_Git_bytes": 2164,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CODECS.json",
      "current_sha256": "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859",
      "current_bytes": 24593,
      "assigned_Git_sha256": "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859",
      "assigned_Git_bytes": 24593,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/DATASTORE-SOURCE-CATALOG.json",
      "current_sha256": "40aae1e46eaaa42a5d9220473b13ebe90af3453a5a6f33e2b947ca6f783752c5",
      "current_bytes": 133600,
      "assigned_Git_sha256": "40aae1e46eaaa42a5d9220473b13ebe90af3453a5a6f33e2b947ca6f783752c5",
      "assigned_Git_bytes": 133600,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/cohorts/core-ts-source-catalog-v1.json",
      "current_sha256": "67828453f4fefc1b4c689507af9064ef1ab48672537a9360dc617da80964343d",
      "current_bytes": 856230,
      "assigned_Git_sha256": "67828453f4fefc1b4c689507af9064ef1ab48672537a9360dc617da80964343d",
      "assigned_Git_bytes": 856230,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CORE-COHORT-SOURCE-CATALOG.json",
      "current_sha256": "b84312bd653e32045e3a19c4b1d0d057b39fd274050e8339016f6197f8f24fce",
      "current_bytes": 67630,
      "assigned_Git_sha256": "b84312bd653e32045e3a19c4b1d0d057b39fd274050e8339016f6197f8f24fce",
      "assigned_Git_bytes": 67630,
      "current_equals_assigned": true
    },
    {
      "path": "scripts/typescript-dev/README.md",
      "current_sha256": "f2b2b79b75edaf87b09927d31c0c345b9e9c4549ae5362655e4ab704da7c6da9",
      "current_bytes": 5329,
      "assigned_Git_sha256": "f2b2b79b75edaf87b09927d31c0c345b9e9c4549ae5362655e4ab704da7c6da9",
      "assigned_Git_bytes": 5329,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/README.md",
      "current_sha256": "2185850836e6660f5ed41876d72737aad80e00997c71b91984c982615b409cc1",
      "current_bytes": 4123,
      "assigned_Git_sha256": "2185850836e6660f5ed41876d72737aad80e00997c71b91984c982615b409cc1",
      "assigned_Git_bytes": 4123,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/src/serialization/exact-json-number-parser.ts",
      "current_sha256": "099505e1b4f9890848d8a159daf75f482bd24e647ba0f01a16c711bfeeebadbc",
      "current_bytes": 9479,
      "assigned_Git_sha256": "099505e1b4f9890848d8a159daf75f482bd24e647ba0f01a16c711bfeeebadbc",
      "assigned_Git_bytes": 9479,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/src/serialization/exact-json-numbers.ts",
      "current_sha256": "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52",
      "current_bytes": 5809,
      "assigned_Git_sha256": "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52",
      "assigned_Git_bytes": 5809,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/src/serialization/exact-json-value.ts",
      "current_sha256": "6e8ac7aff564ac3c488799800f457f3a0e5cb74e1b2c78fb938937355a1acffc",
      "current_bytes": 14254,
      "assigned_Git_sha256": "6e8ac7aff564ac3c488799800f457f3a0e5cb74e1b2c78fb938937355a1acffc",
      "assigned_Git_bytes": 14254,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/src/serialization/canonical-json.ts",
      "current_sha256": "32030fd0eca59af701d2354a374ab91d6393d9ce4a27669433092699cb0ae681",
      "current_bytes": 5701,
      "assigned_Git_sha256": "32030fd0eca59af701d2354a374ab91d6393d9ce4a27669433092699cb0ae681",
      "assigned_Git_bytes": 5701,
      "current_equals_assigned": true
    },
    {
      "path": "packages/healthmd-core-ts/src/serialization/index.ts",
      "current_sha256": "87e14590a6cee520b3f2bf4abc4fae55f581130921691947dd2c4deb05546dbb",
      "current_bytes": 762,
      "assigned_Git_sha256": "87e14590a6cee520b3f2bf4abc4fae55f581130921691947dd2c4deb05546dbb",
      "assigned_Git_bytes": 762,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PARSE-EXACT-JSON-NUMBERS.json",
      "current_sha256": "88fb9788d17a2c777b50eb306db516ec5682623fb4c6ad43c728d0604c324abb",
      "current_bytes": 83618,
      "assigned_Git_sha256": "88fb9788d17a2c777b50eb306db516ec5682623fb4c6ad43c728d0604c324abb",
      "assigned_Git_bytes": 83618,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PARSE-EXACT-JSON-VALUES.json",
      "current_sha256": "9227a4fd1e488fb58f3c68983827e7b4b53712e84ae1a49f349a47cbb7164c5c",
      "current_bytes": 143547,
      "assigned_Git_sha256": "9227a4fd1e488fb58f3c68983827e7b4b53712e84ae1a49f349a47cbb7164c5c",
      "assigned_Git_bytes": 143547,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/SERIALIZE-CANONICAL-JSON.json",
      "current_sha256": "df942abf9eff71fc4b53ffc42968a48e8aff7f47c887910fd05bfd9306bc7e1f",
      "current_bytes": 376555,
      "assigned_Git_sha256": "df942abf9eff71fc4b53ffc42968a48e8aff7f47c887910fd05bfd9306bc7e1f",
      "assigned_Git_bytes": 376555,
      "current_equals_assigned": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CORE-CANDIDATE-CODEC-API.json",
      "current_sha256": "fbf14b4f4a714bd17433a5c3fbe89ccc46b9425d8d94ac6b9921610ecf5d019f",
      "current_bytes": 197544,
      "assigned_Git_sha256": "fbf14b4f4a714bd17433a5c3fbe89ccc46b9425d8d94ac6b9921610ecf5d019f",
      "assigned_Git_bytes": 197544,
      "current_equals_assigned": true
    }
  ],
  "source_ranges": [
    {
      "id": "typed-json",
      "path": "apps/apple/HealthMd/Shared/Query/QueryTypedValue.swift",
      "start_line": 5,
      "end_line": 44,
      "symbol": "HealthMdJSONValue",
      "sha256": "45df842d8a34a0219636e347eb8c88c32172a81881d5bc0114f9cb76c0fd9d2c",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "45df842d8a34a0219636e347eb8c88c32172a81881d5bc0114f9cb76c0fd9d2c",
      "raw_utf8": "/// JSON-shaped payload retained for a typed value introduced by a newer Health.md version.\n/// Numbers are finite by construction; callers never have to interpret JSON null as zero.\nnonisolated indirect enum HealthMdJSONValue: Codable, Equatable, Sendable {\n    case null\n    case string(String)\n    case boolean(Bool)\n    case integer(Int64)\n    case unsignedInteger(UInt64)\n    case number(Double)\n    case array([HealthMdJSONValue])\n    case object([String: HealthMdJSONValue])\n\n    init(from decoder: Decoder) throws {\n        let container = try decoder.singleValueContainer()\n        if container.decodeNil() { self = .null }\n        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }\n        else if let value = try? container.decode(Int64.self) { self = .integer(value) }\n        else if let value = try? container.decode(UInt64.self) { self = .unsignedInteger(value) }\n        else if let value = try? container.decode(Double.self) {\n            guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }\n            self = .number(value)\n        } else if let value = try? container.decode(String.self) { self = .string(value) }\n        else if let value = try? container.decode([HealthMdJSONValue].self) { self = .array(value) }\n        else { self = .object(try container.decode([String: HealthMdJSONValue].self)) }\n    }\n\n    func encode(to encoder: Encoder) throws {\n        var container = encoder.singleValueContainer()\n        switch self {\n        case .null: try container.encodeNil()\n        case .string(let value): try container.encode(value)\n        case .boolean(let value): try container.encode(value)\n        case .integer(let value): try container.encode(value)\n        case .unsignedInteger(let value): try container.encode(value)\n        case .number(let value):\n            guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }\n            try container.encode(value)\n        case .array(let value): try container.encode(value)\n        case .object(let value): try container.encode(value)\n        }\n",
      "current_equals_historical_range": true
    },
    {
      "id": "typed-tags",
      "path": "apps/apple/HealthMd/Shared/Query/QueryTypedValue.swift",
      "start_line": 58,
      "end_line": 166,
      "symbol": "HealthMdQueryValue",
      "sha256": "e4f6dc689a86546631eb7c25ce73a23197875397a71d24b4d695ab442b81848e",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "e4f6dc689a86546631eb7c25ce73a23197875397a71d24b4d695ab442b81848e",
      "raw_utf8": "}\n\n/// A compact, tagged health value. Floating-point values reject NaN and infinities.\nnonisolated indirect enum HealthMdQueryValue: Equatable, Sendable {\n    case quantity(value: Double, unit: String)\n    case duration(seconds: Double)\n    case count(Int64)\n    case string(String)\n    case category(HealthMdCategoryValue)\n    case boolean(Bool)\n    case timestamp(Date)\n    /// An ISO `yyyy-MM-dd` calendar date, intentionally distinct from a timestamp.\n    case date(String)\n    case array([HealthMdQueryValue])\n    /// A forward-compatible tagged value. The original tag and JSON-shaped payload survive decoding.\n    case unknown(type: String, value: HealthMdJSONValue?)\n\n    static func finiteQuantity(_ value: Double, unit: String) throws -> HealthMdQueryValue {\n        guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }\n        return .quantity(value: value, unit: unit)\n    }\n\n    static func finiteDuration(seconds: Double) throws -> HealthMdQueryValue {\n        guard seconds.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }\n        return .duration(seconds: seconds)\n    }\n\n    var finiteNumericValue: Double? {\n        switch self {\n        case .quantity(let value, _): return value.isFinite ? value : nil\n        case .duration(let seconds): return seconds.isFinite ? seconds : nil\n        case .count(let count): return Double(count)\n        default: return nil\n        }\n    }\n\n    var unit: String? {\n        switch self {\n        case .quantity(_, let unit): return unit\n        case .duration: return \"s\"\n        case .count: return \"count\"\n        default: return nil\n        }\n    }\n}\n\nextension HealthMdQueryValue: Codable {\n    private enum CodingKeys: String, CodingKey { case type, value, unit, seconds, identifier, display, rawValue = \"raw_value\" }\n\n    init(from decoder: Decoder) throws {\n        let container = try decoder.container(keyedBy: CodingKeys.self)\n        let type = try container.decode(String.self, forKey: .type)\n        switch type {\n        case \"quantity\":\n            let value = try container.decode(Double.self, forKey: .value)\n            guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }\n            self = .quantity(value: value, unit: try container.decode(String.self, forKey: .unit))\n        case \"duration\":\n            let seconds = try container.decode(Double.self, forKey: .seconds)\n            guard seconds.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }\n            self = .duration(seconds: seconds)\n        case \"count\": self = .count(try container.decode(Int64.self, forKey: .value))\n        case \"string\": self = .string(try container.decode(String.self, forKey: .value))\n        case \"category\": self = .category(HealthMdCategoryValue(\n            identifier: try container.decode(String.self, forKey: .identifier),\n            display: try container.decodeIfPresent(String.self, forKey: .display),\n            rawValue: try container.decodeIfPresent(Int64.self, forKey: .rawValue)\n        ))\n        case \"boolean\": self = .boolean(try container.decode(Bool.self, forKey: .value))\n        case \"timestamp\": self = .timestamp(try container.decode(Date.self, forKey: .value))\n        case \"date\": self = .date(try container.decode(String.self, forKey: .value))\n        case \"array\": self = .array(try container.decode([HealthMdQueryValue].self, forKey: .value))\n        default: self = .unknown(type: type, value: try container.decodeIfPresent(HealthMdJSONValue.self, forKey: .value))\n        }\n    }\n\n    func encode(to encoder: Encoder) throws {\n        var container = encoder.container(keyedBy: CodingKeys.self)\n        switch self {\n        case .quantity(let value, let unit):\n            guard value.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }\n            try container.encode(\"quantity\", forKey: .type)\n            try container.encode(value, forKey: .value)\n            try container.encode(unit, forKey: .unit)\n        case .duration(let seconds):\n            guard seconds.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }\n            try container.encode(\"duration\", forKey: .type)\n            try container.encode(seconds, forKey: .seconds)\n        case .count(let value):\n            try container.encode(\"count\", forKey: .type); try container.encode(value, forKey: .value)\n        case .string(let value):\n            try container.encode(\"string\", forKey: .type); try container.encode(value, forKey: .value)\n        case .category(let value):\n            try container.encode(\"category\", forKey: .type)\n            try container.encode(value.identifier, forKey: .identifier)\n            try container.encodeIfPresent(value.display, forKey: .display)\n            try container.encodeIfPresent(value.rawValue, forKey: .rawValue)\n        case .boolean(let value):\n            try container.encode(\"boolean\", forKey: .type); try container.encode(value, forKey: .value)\n        case .timestamp(let value):\n            try container.encode(\"timestamp\", forKey: .type); try container.encode(value, forKey: .value)\n        case .date(let value):\n            try container.encode(\"date\", forKey: .type); try container.encode(value, forKey: .value)\n        case .array(let value):\n            try container.encode(\"array\", forKey: .type); try container.encode(value, forKey: .value)\n        case .unknown(let type, let value):\n            try container.encode(type, forKey: .type); try container.encodeIfPresent(value, forKey: .value)\n        }\n    }\n",
      "current_equals_historical_range": true
    },
    {
      "id": "metric-selection",
      "path": "apps/apple/HealthMd/Shared/Query/QueryContracts.swift",
      "start_line": 42,
      "end_line": 81,
      "symbol": "HealthMdMetricSelection",
      "sha256": "3e5347afa7b6c9134b26d877e4377273259bcdfea3a88e82dddcc381accbb339",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "3e5347afa7b6c9134b26d877e4377273259bcdfea3a88e82dddcc381accbb339",
      "raw_utf8": "nonisolated enum HealthMdMetricSelection: Codable, Equatable, Sendable {\n    case explicit([String])\n    case allAvailable\n\n    private enum CodingKeys: String, CodingKey { case type, metricIDs = \"metric_ids\" }\n    func encode(to encoder: Encoder) throws {\n        var c = encoder.container(keyedBy: CodingKeys.self)\n        switch self {\n        case .explicit(let ids):\n            try c.encode(\"explicit\", forKey: .type)\n            try c.encode(Array(Set(ids)).sorted(), forKey: .metricIDs)\n        case .allAvailable: try c.encode(\"all_available\", forKey: .type)\n        }\n    }\n    init(from decoder: Decoder) throws {\n        try decoder.rejectUnknownKeys([\"type\", \"metric_ids\"])\n        let c = try decoder.container(keyedBy: CodingKeys.self)\n        switch try c.decode(String.self, forKey: .type) {\n        case \"explicit\":\n            let ids = try c.decode([String].self, forKey: .metricIDs)\n            guard Set(ids).count == ids.count else {\n                throw DecodingError.dataCorruptedError(\n                    forKey: .metricIDs,\n                    in: c,\n                    debugDescription: \"Duplicate metric IDs are not allowed\"\n                )\n            }\n            self = .explicit(ids.sorted())\n        case \"all_available\":\n            guard !c.contains(.metricIDs) else {\n                throw DecodingError.dataCorruptedError(\n                    forKey: .metricIDs,\n                    in: c,\n                    debugDescription: \"all_available cannot include metric_ids\"\n                )\n            }\n            self = .allAvailable\n        default:\n            throw DecodingError.dataCorruptedError(\n                forKey: .type,\n",
      "current_equals_historical_range": true
    },
    {
      "id": "source-selection",
      "path": "apps/apple/HealthMd/Shared/Query/QueryContracts.swift",
      "start_line": 99,
      "end_line": 160,
      "symbol": "HealthMdSourceSelection",
      "sha256": "ef2bd1d5d5c32aa0111a2fa1081759871c37ebc24ee5c4ce5e10d87ed660d656",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "ef2bd1d5d5c32aa0111a2fa1081759871c37ebc24ee5c4ce5e10d87ed660d656",
      "raw_utf8": "nonisolated enum HealthMdSourceSelection: Codable, Equatable, Sendable {\n    case explicit(sourceIDs: [String], providerIDs: [String])\n    case allAvailable\n\n    private enum CodingKeys: String, CodingKey {\n        case type\n        case sourceIDs = \"source_ids\"\n        case providerIDs = \"provider_ids\"\n    }\n\n    func encode(to encoder: Encoder) throws {\n        var container = encoder.container(keyedBy: CodingKeys.self)\n        switch self {\n        case .explicit(let sourceIDs, let providerIDs):\n            try container.encode(\"explicit\", forKey: .type)\n            try container.encode(Array(Set(sourceIDs)).sorted(), forKey: .sourceIDs)\n            try container.encode(Array(Set(providerIDs)).sorted(), forKey: .providerIDs)\n        case .allAvailable:\n            try container.encode(\"all_available\", forKey: .type)\n        }\n    }\n\n    init(from decoder: Decoder) throws {\n        try decoder.rejectUnknownKeys([\"type\", \"source_ids\", \"provider_ids\"])\n        let container = try decoder.container(keyedBy: CodingKeys.self)\n        switch try container.decode(String.self, forKey: .type) {\n        case \"explicit\":\n            let sourceIDs = try container.decodeIfPresent([String].self, forKey: .sourceIDs) ?? []\n            let providerIDs = try container.decodeIfPresent([String].self, forKey: .providerIDs) ?? []\n            guard Set(sourceIDs).count == sourceIDs.count else {\n                throw DecodingError.dataCorruptedError(\n                    forKey: .sourceIDs,\n                    in: container,\n                    debugDescription: \"Duplicate source IDs are not allowed\"\n                )\n            }\n            guard Set(providerIDs).count == providerIDs.count else {\n                throw DecodingError.dataCorruptedError(\n                    forKey: .providerIDs,\n                    in: container,\n                    debugDescription: \"Duplicate provider IDs are not allowed\"\n                )\n            }\n            self = .explicit(\n                sourceIDs: sourceIDs.sorted(),\n                providerIDs: providerIDs.sorted()\n            )\n        case \"all_available\":\n            guard !container.contains(.sourceIDs), !container.contains(.providerIDs) else {\n                throw DecodingError.dataCorruptedError(\n                    forKey: container.contains(.sourceIDs) ? .sourceIDs : .providerIDs,\n                    in: container,\n                    debugDescription: \"all_available cannot include explicit sources\"\n                )\n            }\n            self = .allAvailable\n        default:\n            throw DecodingError.dataCorruptedError(\n                forKey: .type,\n                in: container,\n                debugDescription: \"Unknown source selection\"\n            )\n",
      "current_equals_historical_range": true
    },
    {
      "id": "coverage-request",
      "path": "apps/apple/HealthMd/Shared/Query/QueryContracts.swift",
      "start_line": 384,
      "end_line": 455,
      "symbol": "HealthMdPageControls",
      "sha256": "766442a21370bc4daf634de1a798cb440ea3ef438a58cc5ceb0129c09c783c1e",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "766442a21370bc4daf634de1a798cb440ea3ef438a58cc5ceb0129c09c783c1e",
      "raw_utf8": "        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: \"Unknown query operation\")\n        }\n    }\n}\n\nnonisolated struct HealthMdPageControls: Codable, Equatable, Sendable {\n    /// Per-page bounds protect memory and wire frames. They never cap total\n    /// query results because every non-terminal page returns a cursor.\n    static let maximumItems = 1_000\n    static let maximumBytes = 1 * 1_024 * 1_024\n\n    let maxItems: Int\n    let maxBytes: Int\n    let cursor: String?\n    init(maxItems: Int = 250, maxBytes: Int = 256 * 1024, cursor: String? = nil) {\n        self.maxItems = maxItems; self.maxBytes = maxBytes; self.cursor = cursor\n    }\n    enum CodingKeys: String, CodingKey { case maxItems = \"max_items\", maxBytes = \"max_bytes\", cursor }\n\n    init(from decoder: Decoder) throws {\n        try decoder.rejectUnknownKeys([\"max_items\", \"max_bytes\", \"cursor\"])\n        let container = try decoder.container(keyedBy: CodingKeys.self)\n        maxItems = try container.decode(Int.self, forKey: .maxItems)\n        maxBytes = try container.decode(Int.self, forKey: .maxBytes)\n        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)\n    }\n}\n\nnonisolated struct HealthMdQueryRequest: Codable, Equatable, Sendable {\n    let schema: String\n    let schemaVersion: Int\n    let metrics: HealthMdMetricSelection\n    let sources: HealthMdSourceSelection\n    let dates: HealthMdDateSelection\n    let operation: HealthMdQueryOperation\n    let page: HealthMdPageControls\n\n    init(\n        metrics: HealthMdMetricSelection,\n        sources: HealthMdSourceSelection = .allAvailable,\n        dates: HealthMdDateSelection,\n        operation: HealthMdQueryOperation,\n        page: HealthMdPageControls = .init(),\n        schema: String = HealthMdQuerySchemas.queryRequest,\n        schemaVersion: Int = 1\n    ) {\n        self.schema = schema\n        self.schemaVersion = schemaVersion\n        self.metrics = metrics\n        self.sources = sources\n        self.dates = dates\n        self.operation = operation\n        self.page = page\n    }\n\n    enum CodingKeys: String, CodingKey {\n        case schema\n        case schemaVersion = \"schema_version\"\n        case metrics, sources, dates, operation, page\n    }\n\n    init(from decoder: Decoder) throws {\n        try decoder.rejectUnknownKeys([\n            \"schema\", \"schema_version\", \"metrics\", \"sources\", \"dates\", \"operation\", \"page\"\n        ])\n        let container = try decoder.container(keyedBy: CodingKeys.self)\n        schema = try container.decode(String.self, forKey: .schema)\n        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)\n        metrics = try container.decode(HealthMdMetricSelection.self, forKey: .metrics)\n        sources = try container.decodeIfPresent(HealthMdSourceSelection.self, forKey: .sources) ?? .allAvailable\n        dates = try container.decode(HealthMdDateSelection.self, forKey: .dates)\n        operation = try container.decode(HealthMdQueryOperation.self, forKey: .operation)\n",
      "current_equals_historical_range": true
    },
    {
      "id": "availability-coverage",
      "path": "apps/apple/HealthMd/Shared/Query/QueryContracts.swift",
      "start_line": 474,
      "end_line": 523,
      "symbol": "HealthMdCoverage",
      "sha256": "b20e4e1bc05b9fe7cb719789e6b8999984c32b3520e6bec90fef335051de0163",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "b20e4e1bc05b9fe7cb719789e6b8999984c32b3520e6bec90fef335051de0163",
      "raw_utf8": "// MARK: - Missingness, coverage, and evidence\n\nnonisolated enum HealthMdAvailabilityStatus: String, Codable, CaseIterable, Sendable {\n    case available\n    case completeEmpty = \"complete_empty\"\n    case partial\n    case failed\n    case unsupported\n    case skipped\n    case cancelled\n    case notRequested = \"not_requested\"\n    case legacyUnavailable = \"legacy_unavailable\"\n    case redacted\n    case notSynchronized = \"not_synchronized\"\n}\n\nnonisolated struct HealthMdMissingInterval: Codable, Equatable, Sendable {\n    let range: HealthMdDateRange\n    let status: HealthMdAvailabilityStatus\n    let reason: String?\n    init(range: HealthMdDateRange, status: HealthMdAvailabilityStatus, reason: String? = nil) {\n        self.range = range; self.status = status; self.reason = reason\n    }\n}\n\nnonisolated struct HealthMdCoverage: Codable, Equatable, Sendable {\n    let requestedRange: HealthMdDateRange?\n    let availableRange: HealthMdDateRange?\n    let status: HealthMdAvailabilityStatus\n    let daysConsidered: Int\n    let daysWithValues: Int\n    let missing: [HealthMdMissingInterval]\n    let missingIntervalCount: Int?\n    let missingTruncated: Bool?\n    init(requestedRange: HealthMdDateRange?, availableRange: HealthMdDateRange?, status: HealthMdAvailabilityStatus, daysConsidered: Int, daysWithValues: Int, missing: [HealthMdMissingInterval] = []) {\n        self.requestedRange = requestedRange; self.availableRange = availableRange; self.status = status\n        self.daysConsidered = daysConsidered; self.daysWithValues = daysWithValues\n        let sortedMissing = missing.sorted { $0.range.startDate < $1.range.startDate }\n        let maximumIntervals = 64\n        self.missing = Array(sortedMissing.prefix(maximumIntervals))\n        self.missingIntervalCount = sortedMissing.count > maximumIntervals ? sortedMissing.count : nil\n        self.missingTruncated = sortedMissing.count > maximumIntervals ? true : nil\n    }\n    enum CodingKeys: String, CodingKey {\n        case requestedRange = \"requested_range\", availableRange = \"available_range\", status\n        case daysConsidered = \"days_considered\", daysWithValues = \"days_with_values\", missing\n        case missingIntervalCount = \"missing_interval_count\", missingTruncated = \"missing_truncated\"\n    }\n}\n\n",
      "current_equals_historical_range": true
    },
    {
      "id": "compact-context",
      "path": "apps/apple/HealthMd/Shared/Query/QueryContracts.swift",
      "start_line": 827,
      "end_line": 867,
      "symbol": "HealthMdCompactContextDay",
      "sha256": "365b938b71dcd57a8e582c50f30f8055cf373f107bddd7e63378eef8e241305e",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "365b938b71dcd57a8e582c50f30f8055cf373f107bddd7e63378eef8e241305e",
      "raw_utf8": "nonisolated struct HealthMdCompactContextDay: Codable, Equatable, Sendable {\n    let schema: String\n    let schemaVersion: Int\n    let ownerDate: String\n    let intervalStart: Date\n    let intervalEnd: Date\n    let calendarTimeZone: String\n    let source: HealthMdSourceDescriptor\n    let status: HealthMdAvailabilityStatus\n    let metrics: [HealthMdContextMetric]\n    let workouts: [HealthMdContextWorkout]\n    let sleepSessions: [HealthMdContextSleepSession]\n    let evidence: [HealthMdContextEvidence]\n    let limitations: [HealthMdLimitation]\n\n    init(ownerDate: String, intervalStart: Date, intervalEnd: Date, calendarTimeZone: String, source: HealthMdSourceDescriptor, status: HealthMdAvailabilityStatus, metrics: [HealthMdContextMetric] = [], workouts: [HealthMdContextWorkout] = [], sleepSessions: [HealthMdContextSleepSession] = [], evidence: [HealthMdContextEvidence] = [], limitations: [HealthMdLimitation] = [], schema: String = HealthMdQuerySchemas.compactContextDay, schemaVersion: Int = 1) {\n        self.schema = schema; self.schemaVersion = schemaVersion; self.ownerDate = ownerDate\n        self.intervalStart = intervalStart; self.intervalEnd = intervalEnd; self.calendarTimeZone = calendarTimeZone\n        self.source = source; self.status = status\n        self.metrics = metrics.sorted { $0.metricID != $1.metricID ? $0.metricID < $1.metricID : $0.observationID < $1.observationID }\n        self.workouts = workouts.sorted { $0.start != $1.start ? $0.start < $1.start : $0.workoutID < $1.workoutID }\n        self.sleepSessions = sleepSessions.sorted { $0.start != $1.start ? $0.start < $1.start : $0.sessionID < $1.sessionID }\n        self.evidence = evidence.sorted { $0.reference.evidenceID < $1.reference.evidenceID }\n        self.limitations = limitations.sorted { $0.code < $1.code }\n    }\n    enum CodingKeys: String, CodingKey { case schema, schemaVersion = \"schema_version\", ownerDate = \"owner_date\", intervalStart = \"interval_start\", intervalEnd = \"interval_end\", calendarTimeZone = \"calendar_timezone\", source, status, metrics, workouts, sleepSessions = \"sleep_sessions\", evidence, limitations }\n\n    init(from decoder: Decoder) throws {\n        let container = try decoder.container(keyedBy: CodingKeys.self)\n        schema = try container.decode(String.self, forKey: .schema)\n        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)\n        ownerDate = try container.decode(String.self, forKey: .ownerDate)\n        intervalStart = try container.decode(Date.self, forKey: .intervalStart)\n        intervalEnd = try container.decode(Date.self, forKey: .intervalEnd)\n        calendarTimeZone = try container.decode(String.self, forKey: .calendarTimeZone)\n        source = try container.decode(HealthMdSourceDescriptor.self, forKey: .source)\n        status = try container.decode(HealthMdAvailabilityStatus.self, forKey: .status)\n        metrics = try container.decodeIfPresent([HealthMdContextMetric].self, forKey: .metrics) ?? []\n        workouts = try container.decodeIfPresent([HealthMdContextWorkout].self, forKey: .workouts) ?? []\n        sleepSessions = try container.decodeIfPresent([HealthMdContextSleepSession].self, forKey: .sleepSessions) ?? []\n        evidence = try container.decodeIfPresent([HealthMdContextEvidence].self, forKey: .evidence) ?? []\n",
      "current_equals_historical_range": true
    },
    {
      "id": "response",
      "path": "apps/apple/HealthMd/Shared/Query/QueryContracts.swift",
      "start_line": 1077,
      "end_line": 1148,
      "symbol": "HealthMdQueryResponse",
      "sha256": "a5a67537e533639f2dd1ab12c648484f84e323913c53499a1e360c250354d59f",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "a5a67537e533639f2dd1ab12c648484f84e323913c53499a1e360c250354d59f",
      "raw_utf8": "nonisolated struct HealthMdQueryResponse: Codable, Equatable, Sendable {\n    let schema: String\n    let schemaVersion: Int\n    let items: [HealthMdQueryItem]\n    let packet: HealthMdEvidencePacket?\n    let coverage: HealthMdCoverage\n    let sources: [HealthMdSourceDescriptor]\n    let evidence: [HealthMdEvidenceReference]\n    let nextCursor: String?\n    let limitations: [HealthMdLimitation]\n    let metadata: [String: HealthMdJSONValue]?\n\n    init(\n        items: [HealthMdQueryItem],\n        packet: HealthMdEvidencePacket?,\n        coverage: HealthMdCoverage,\n        sources: [HealthMdSourceDescriptor],\n        evidence: [HealthMdEvidenceReference],\n        nextCursor: String?,\n        limitations: [HealthMdLimitation],\n        metadata: [String: HealthMdJSONValue]? = nil,\n        schema: String = HealthMdQuerySchemas.queryResponse,\n        schemaVersion: Int = HealthMdQuerySchemas.version\n    ) {\n        self.schema = schema\n        self.schemaVersion = schemaVersion\n        self.items = items\n        self.packet = packet\n        self.coverage = coverage\n        let maximumSourceDescriptors = 64\n        self.sources = Array(sources.prefix(maximumSourceDescriptors))\n        self.evidence = evidence\n        self.nextCursor = nextCursor\n        var boundedLimitations = limitations\n        if sources.count > maximumSourceDescriptors {\n            boundedLimitations.append(.init(\n                code: \"source_descriptors_truncated\",\n                message: \"Additional source descriptors were omitted from this bounded response page.\"\n            ))\n        }\n        if coverage.missingTruncated == true {\n            boundedLimitations.append(.init(\n                code: \"coverage_intervals_truncated\",\n                message: \"Additional missing intervals were omitted; inspect missing_interval_count.\"\n            ))\n        }\n        let sortedLimitations = Array(Set(boundedLimitations)).sorted {\n            $0.code != $1.code ? $0.code < $1.code : $0.message < $1.message\n        }\n        if sortedLimitations.count > 64 {\n            var retained = Array(sortedLimitations.prefix(62))\n            if let factualOnly = sortedLimitations.first(where: { $0.code == \"factual_observations_only\" }),\n               !retained.contains(factualOnly) {\n                retained.append(factualOnly)\n            }\n            retained.append(.init(\n                code: \"limitations_truncated\",\n                message: \"Additional limitations were omitted from this bounded response page.\"\n            ))\n            self.limitations = retained.sorted { $0.code < $1.code }\n        } else {\n            self.limitations = sortedLimitations\n        }\n        self.metadata = metadata\n    }\n\n    enum CodingKeys: String, CodingKey {\n        case schema, schemaVersion = \"schema_version\", items, packet, coverage, sources, evidence\n        case nextCursor = \"next_cursor\"\n        case limitations, metadata\n    }\n}\n",
      "current_equals_historical_range": true
    },
    {
      "id": "scope",
      "path": "apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift",
      "start_line": 400,
      "end_line": 465,
      "symbol": "validateScope",
      "sha256": "bc7c4dca9db630d0db17bd04473b0cd7f60819d98a4f1dc0db41f0818d3b5c17",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "bc7c4dca9db630d0db17bd04473b0cd7f60819d98a4f1dc0db41f0818d3b5c17",
      "raw_utf8": "  private func validateScope(\n    _ request: HealthMdQueryRequest,\n    scope: HealthMdEvidenceScope?\n  ) throws {\n    guard let scope else {\n      if case .sourceRecordListing = request.operation {\n        throw HealthMdQueryContractError.scopeViolation(\"missing_evidence_scope\")\n      }\n      return\n    }\n    if case .explicit(let metricIDs) = request.metrics {\n      let denied = Set(metricIDs).subtracting(scope.allowedMetricIDs)\n      guard denied.isEmpty else {\n        throw HealthMdQueryContractError.scopeViolation(\n          \"metric_ids:\\(denied.sorted().joined(separator: \",\"))\")\n      }\n    }\n    if case .explicit(let sourceIDs, let providerIDs) = request.sources {\n      if let allowed = scope.allowedSourceIDs {\n        let denied = Set(sourceIDs).subtracting(allowed)\n        guard denied.isEmpty else {\n          throw HealthMdQueryContractError.scopeViolation(\n            \"source_ids:\\(denied.sorted().joined(separator: \",\"))\")\n        }\n      }\n      if let allowed = scope.allowedProviderIDs {\n        let denied = Set(providerIDs).subtracting(allowed)\n        guard denied.isEmpty else {\n          throw HealthMdQueryContractError.scopeViolation(\n            \"provider_ids:\\(denied.sorted().joined(separator: \",\"))\")\n        }\n      }\n    }\n    if case .workoutListing = request.operation, !scope.allowsWorkouts {\n      throw HealthMdQueryContractError.scopeViolation(\"workouts\")\n    }\n    switch request.operation {\n    case .sleepSessionListing(let window, _):\n      try HealthMdSleepSessionQuery.validate(window: window)\n      guard\n        HealthMdSleepSessionQuery.hasSleepAuthorization(\n          selection: request.metrics,\n          allowedMetricIDs: scope.allowedMetricIDs\n        )\n      else {\n        throw HealthMdQueryContractError.scopeViolation(\"sleep_sessions\")\n      }\n    case .workoutSleepAlignment(let window, let activity, _):\n      try HealthMdSleepSessionQuery.validate(window: window)\n      guard scope.allowsWorkouts else {\n        throw HealthMdQueryContractError.scopeViolation(\"workouts\")\n      }\n      guard\n        HealthMdSleepSessionQuery.hasSleepAuthorization(\n          selection: request.metrics,\n          allowedMetricIDs: scope.allowedMetricIDs\n        )\n      else {\n        throw HealthMdQueryContractError.scopeViolation(\"sleep_sessions\")\n      }\n      if let activity, activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n        throw HealthMdQueryContractError.unsupportedOperation\n      }\n    default:\n      break\n    }\n",
      "current_equals_historical_range": true
    },
    {
      "id": "coverage-dispatch",
      "path": "apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift",
      "start_line": 221,
      "end_line": 230,
      "symbol": "case .coverage",
      "sha256": "f76d9e54ebf1f8f2c50d076475edaccd2bd45a73f335e9956422ebf7d96915e8",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "f76d9e54ebf1f8f2c50d076475edaccd2bd45a73f335e9956422ebf7d96915e8",
      "raw_utf8": "    case .coverage:\n      guard offset == 0 else { throw HealthMdQueryContractError.invalidCursor }\n      return HealthMdQueryResponse(\n        items: [], packet: nil,\n        coverage: coverage(\n          for: selectedDays, requested: request.dates,\n          valueDays: Set(selectedDays.filter(hasAnyValue).map(\\.ownerDate))),\n        sources: normalizedSources(selectedDays), evidence: [],\n        nextCursor: nil, limitations: allLimitations(in: selectedDays)\n      )\n",
      "current_equals_historical_range": true
    },
    {
      "id": "coverage-counts",
      "path": "apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift",
      "start_line": 1293,
      "end_line": 1334,
      "symbol": "private func coverage",
      "sha256": "f41442dc82cea098600a10006c752cbc55d8f7153f085b43ded941c579a50262",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "f41442dc82cea098600a10006c752cbc55d8f7153f085b43ded941c579a50262",
      "raw_utf8": "  private func coverage(\n    for selectedDays: [HealthMdCompactContextDay],\n    requested: HealthMdDateSelection,\n    valueDays: Set<String>\n  ) -> HealthMdCoverage {\n    let requestedRange = selectedRange(requested, selectedDays: selectedDays)\n    let availableRange = days.first.flatMap { first in\n      days.last.map { HealthMdDateRange(startDate: first.ownerDate, endDate: $0.ownerDate) }\n    }\n    let missing = selectedDays.compactMap { day -> HealthMdMissingInterval? in\n      let status: HealthMdAvailabilityStatus\n      if valueDays.contains(day.ownerDate) { return nil }\n      if day.status == .available { status = .completeEmpty } else { status = day.status }\n      return .init(range: .init(startDate: day.ownerDate, endDate: day.ownerDate), status: status)\n    }\n    let status: HealthMdAvailabilityStatus\n    if selectedDays.isEmpty {\n      status = .notSynchronized\n    } else if missing.isEmpty {\n      status = .available\n    } else if valueDays.isEmpty {\n      let statuses = Set(missing.map(\\.status))\n      status = statuses.count == 1 ? statuses.first! : .partial\n    } else {\n      status = .partial\n    }\n    return HealthMdCoverage(\n      requestedRange: requestedRange, availableRange: availableRange, status: status,\n      daysConsidered: selectedDays.count, daysWithValues: valueDays.count, missing: missing\n    )\n  }\n\n  private func selectedRange(\n    _ selection: HealthMdDateSelection, selectedDays: [HealthMdCompactContextDay]\n  ) -> HealthMdDateRange? {\n    switch selection {\n    case .exact(let range): return range\n    case .allAvailable:\n      guard let first = selectedDays.first, let last = selectedDays.last else { return nil }\n      return .init(startDate: first.ownerDate, endDate: last.ownerDate)\n    }\n  }\n",
      "current_equals_historical_range": true
    },
    {
      "id": "coverage-presence",
      "path": "apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift",
      "start_line": 1344,
      "end_line": 1355,
      "symbol": "private func hasAnyValue",
      "sha256": "8c041864327ee6e5754086ba31d7804761f1bf74e7e45254640825ce408273ad",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "8c041864327ee6e5754086ba31d7804761f1bf74e7e45254640825ce408273ad",
      "raw_utf8": "  private func hasAnyValue(_ day: HealthMdCompactContextDay) -> Bool {\n    day.metrics.contains { $0.value != nil && $0.status == .available }\n      || !day.workouts.isEmpty\n      || !day.sleepSessions.isEmpty\n  }\n\n  private func allLimitations(in days: [HealthMdCompactContextDay]) -> [HealthMdLimitation] {\n    uniqueLimitations(\n      days.flatMap(\\.limitations)\n        + days.flatMap { $0.metrics.flatMap(\\.limitations) }\n        + days.flatMap { $0.sleepSessions.flatMap(\\.limitations) }\n    )\n",
      "current_equals_historical_range": true
    },
    {
      "id": "cursor-preimage",
      "path": "apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift",
      "start_line": 1466,
      "end_line": 1569,
      "symbol": "private struct RequestFingerprint",
      "sha256": "a80a84e432ecb84202549d4d8d4b5f9316e0e9854403fc88777b996285b1e08e",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "a80a84e432ecb84202549d4d8d4b5f9316e0e9854403fc88777b996285b1e08e",
      "raw_utf8": "  private struct RequestFingerprint: Encodable {\n    let schema: String\n    let schemaVersion: Int\n    let metrics: HealthMdMetricSelection\n    let sources: HealthMdSourceSelection\n    let dates: HealthMdDateSelection\n    let operation: HealthMdQueryOperation\n    let maxItems: Int\n    let maxBytes: Int\n    enum CodingKeys: String, CodingKey {\n      case schema\n      case schemaVersion = \"schema_version\"\n      case metrics, sources, dates, operation\n      case maxItems = \"max_items\"\n      case maxBytes = \"max_bytes\"\n    }\n  }\n\n  private func requestFingerprint(_ request: HealthMdQueryRequest) throws -> String {\n    try HealthMdQueryCanonicalSerializer.sha256(\n      of: RequestFingerprint(\n        schema: request.schema,\n        schemaVersion: request.schemaVersion,\n        metrics: request.metrics,\n        sources: request.sources,\n        dates: request.dates,\n        operation: request.operation,\n        maxItems: request.page.maxItems,\n        maxBytes: request.page.maxBytes\n      ))\n  }\n\n  private struct CursorPayload: Codable {\n    let offset: Int\n    let query: String\n    let dataset: String\n    let binding: String\n  }\n  private struct CursorEnvelope: Codable {\n    let payload: String\n    let mac: String\n  }\n\n  private func makeCursor(offset: Int, fingerprint: String) throws -> String {\n    let payload = CursorPayload(\n      offset: offset,\n      query: fingerprint,\n      dataset: datasetFingerprint,\n      binding: cursorBinding\n    )\n    let payloadData = try HealthMdQueryCanonicalSerializer.data(for: payload)\n    let payloadString = base64URL(payloadData)\n    let mac = HMAC<SHA256>.authenticationCode(\n      for: Data(payloadString.utf8), using: SymmetricKey(data: cursorKey))\n    let envelope = CursorEnvelope(\n      payload: payloadString, mac: Data(mac).map { String(format: \"%02x\", $0) }.joined())\n    return base64URL(try HealthMdQueryCanonicalSerializer.data(for: envelope))\n  }\n\n  private func cursorOffset(_ cursor: String?, fingerprint: String) throws -> Int {\n    guard let cursor else { return 0 }\n    guard let envelopeData = decodeBase64URL(cursor),\n      let envelope = try? JSONDecoder().decode(CursorEnvelope.self, from: envelopeData),\n      let payloadData = decodeBase64URL(envelope.payload),\n      let payload = try? JSONDecoder().decode(CursorPayload.self, from: payloadData)\n    else {\n      throw HealthMdQueryContractError.invalidCursor\n    }\n    let expected = HMAC<SHA256>.authenticationCode(\n      for: Data(envelope.payload.utf8), using: SymmetricKey(data: cursorKey))\n    let expectedHex = Data(expected).map { String(format: \"%02x\", $0) }.joined()\n    guard constantTimeEqual(expectedHex, envelope.mac) else {\n      throw HealthMdQueryContractError.invalidCursor\n    }\n    guard payload.query == fingerprint,\n      payload.dataset == datasetFingerprint,\n      payload.binding == cursorBinding\n    else {\n      throw HealthMdQueryContractError.cursorDoesNotMatchQuery\n    }\n    return payload.offset\n  }\n\n  private func base64URL(_ data: Data) -> String {\n    data.base64EncodedString().replacingOccurrences(of: \"+\", with: \"-\").replacingOccurrences(\n      of: \"/\", with: \"_\"\n    ).replacingOccurrences(of: \"=\", with: \"\")\n  }\n\n  private func decodeBase64URL(_ value: String) -> Data? {\n    var base64 = value.replacingOccurrences(of: \"-\", with: \"+\").replacingOccurrences(\n      of: \"_\", with: \"/\")\n    base64 += String(repeating: \"=\", count: (4 - base64.count % 4) % 4)\n    return Data(base64Encoded: base64)\n  }\n\n  private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {\n    let a = Array(lhs.utf8)\n    let b = Array(rhs.utf8)\n    guard a.count == b.count else { return false }\n    var difference: UInt8 = 0\n    for index in a.indices { difference |= a[index] ^ b[index] }\n    return difference == 0\n  }\n",
      "current_equals_historical_range": true
    },
    {
      "id": "query-canonical-profile",
      "path": "apps/apple/HealthMd/Shared/Query/QueryCanonicalSerializer.swift",
      "start_line": 107,
      "end_line": 134,
      "symbol": "private static func encoder",
      "sha256": "d6258b90d6d7e934f09afbc71d41ac2759dc319b6244f68cce3409423181f6df",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "d6258b90d6d7e934f09afbc71d41ac2759dc319b6244f68cce3409423181f6df",
      "raw_utf8": "    private static func encoder() -> JSONEncoder {\n        let encoder = JSONEncoder()\n        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]\n        encoder.dateEncodingStrategy = .custom { date, encoder in\n            var container = encoder.singleValueContainer()\n            try container.encode(CanonicalRFC3339UTC.string(from: date))\n        }\n        // `.throw` is intentional: NaN and infinities are never valid query values.\n        encoder.nonConformingFloatEncodingStrategy = .throw\n        return encoder\n    }\n\n    private static func decoder() -> JSONDecoder {\n        let decoder = JSONDecoder()\n        decoder.dateDecodingStrategy = .custom { decoder in\n            let value = try decoder.singleValueContainer().decode(String.self)\n            guard let date = CanonicalRFC3339UTC.date(from: value) else {\n                throw DecodingError.dataCorrupted(\n                    .init(codingPath: decoder.codingPath, debugDescription: \"Invalid canonical RFC 3339 timestamp\")\n                )\n            }\n            return date\n        }\n        decoder.nonConformingFloatDecodingStrategy = .throw\n        return decoder\n    }\n\n    private struct SemanticPacket: Encodable {\n",
      "current_equals_historical_range": true
    },
    {
      "id": "native-timestamp",
      "path": "apps/apple/HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift",
      "start_line": 254,
      "end_line": 315,
      "symbol": "CanonicalRFC3339UTC",
      "sha256": "733a331267f8bfe25aa7a1af406564a3de853db667fc684da2870c280065a818",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "733a331267f8bfe25aa7a1af406564a3de853db667fc684da2870c280065a818",
      "raw_utf8": "nonisolated enum CanonicalRFC3339UTC {\n    private static let formatterThreadKey = \"healthmd.canonical-rfc3339-whole-seconds\"\n\n    private static func cachedFormatterForCurrentThread() -> ISO8601DateFormatter {\n        if let formatter = Thread.current.threadDictionary[formatterThreadKey]\n            as? ISO8601DateFormatter {\n            return formatter\n        }\n        let formatter = ISO8601DateFormatter()\n        formatter.formatOptions = [.withInternetDateTime]\n        formatter.timeZone = TimeZone(secondsFromGMT: 0)\n        Thread.current.threadDictionary[formatterThreadKey] = formatter\n        return formatter\n    }\n\n    static func string(from date: Date) -> String {\n        let interval = date.timeIntervalSince1970\n        var wholeSeconds = floor(interval)\n        var nanoseconds = Int(((interval - wholeSeconds) * 1_000_000_000).rounded())\n        if nanoseconds == 1_000_000_000 {\n            wholeSeconds += 1\n            nanoseconds = 0\n        }\n\n        let whole = cachedFormatterForCurrentThread().string(\n            from: Date(timeIntervalSince1970: wholeSeconds)\n        )\n        let prefix = whole.hasSuffix(\"Z\") ? String(whole.dropLast()) : whole\n        return String(format: \"%@.%09dZ\", prefix, nanoseconds)\n    }\n\n    /// Parses only timestamps emitted by `string(from:)` and verifies that Foundation's\n    /// floating-point `Date` representation can reproduce the exact canonical bytes.\n    static func date(from value: String) -> Date? {\n        guard value.last == \"Z\", value.count >= 12 else { return nil }\n\n        let decimalIndex = value.index(value.endIndex, offsetBy: -11)\n        let fractionalStart = value.index(after: decimalIndex)\n        let utcSuffixIndex = value.index(before: value.endIndex)\n        guard value[decimalIndex] == \".\" else { return nil }\n\n        let fractional = value[fractionalStart..<utcSuffixIndex]\n        guard fractional.count == 9,\n              fractional.allSatisfy({ $0.isASCII && $0.isNumber }),\n              let nanoseconds = Int(fractional) else {\n            return nil\n        }\n\n        let wholeSecondsValue = String(value[..<decimalIndex]) + \"Z\"\n        guard let wholeSeconds = cachedFormatterForCurrentThread().date(from: wholeSecondsValue) else {\n            return nil\n        }\n\n        let parsed = wholeSeconds.addingTimeInterval(Double(nanoseconds) / 1_000_000_000)\n        guard string(from: parsed) == value else { return nil }\n        return parsed\n    }\n}\n\n/// RFC 4180 field escaping shared by all daily CSV rows that can contain arbitrary text.\nnonisolated enum CSVFieldEscaper {\n    static func escape(_ value: String) -> String {\n",
      "current_equals_historical_range": true
    },
    {
      "id": "android-query-compat",
      "path": "apps/android/direct-protocol/src/main/kotlin/com/healthmd/direct/protocol/ProtocolModels.kt",
      "start_line": 86,
      "end_line": 93,
      "symbol": "val query: JsonObject? = null",
      "sha256": "4d5c5e2ecd14786ede28d6174aefff08efeaa3faafe85f924b136cf7ee5e8f28",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_range_sha256": "4d5c5e2ecd14786ede28d6174aefff08efeaa3faafe85f924b136cf7ee5e8f28",
      "raw_utf8": "    val transfer: TransferCapabilities,\n    // iOS query protocol v3 is advertised on the shared v1 hello. Android does not use the\n    // capability, but must decode a current CLI hello without weakening strict unknown-key checks.\n    val query: JsonObject? = null,\n    // RFC-0005 P2 wake enrollment uses the same additive hello capability. Android (P3) does not\n    // enroll yet, but must still decode a current CLI hello strictly.\n    val wake: JsonObject? = null,\n)\n",
      "current_equals_historical_range": true
    }
  ],
  "native_fixture_locators": [
    {
      "id": "testCanonicalBytesAreStableAndRejectNonFiniteValues",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 8,
      "end_line": 31,
      "symbol": "testCanonicalBytesAreStableAndRejectNonFiniteValues",
      "sha256": "277853adc2eb0ce2a46ab2257a5439b3b2e0914465fc735db7bd7ea4b39805b6",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "277853adc2eb0ce2a46ab2257a5439b3b2e0914465fc735db7bd7ea4b39805b6",
      "raw_utf8": "  func testCanonicalBytesAreStableAndRejectNonFiniteValues() throws {\n    let value = HealthMdQueryValue.array([\n      .quantity(value: 12.5, unit: \"km\"), .duration(seconds: 60), .count(3),\n      .string(\"x\"), .category(.init(identifier: \"asleep\", display: \"Asleep\", rawValue: 2)),\n      .boolean(true), .timestamp(Date(timeIntervalSince1970: 1_700_000_000.125)),\n      .date(\"2026-03-08\"), .unknown(type: \"future_value\", value: .object([\"z\": .integer(1)])),\n    ])\n    let first = try HealthMdQueryCanonicalSerializer.data(for: value)\n    let second = try HealthMdQueryCanonicalSerializer.data(for: value)\n    XCTAssertEqual(first, second)\n    XCTAssertEqual(\n      try HealthMdQueryCanonicalSerializer.decode(HealthMdQueryValue.self, from: first), value)\n    XCTAssertEqual(\n      String(decoding: first, as: UTF8.self),\n      #\"{\"type\":\"array\",\"value\":[{\"type\":\"quantity\",\"unit\":\"km\",\"value\":12.5},{\"seconds\":60,\"type\":\"duration\"},{\"type\":\"count\",\"value\":3},{\"type\":\"string\",\"value\":\"x\"},{\"display\":\"Asleep\",\"identifier\":\"asleep\",\"raw_value\":2,\"type\":\"category\"},{\"type\":\"boolean\",\"value\":true},{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.125000000Z\"},{\"type\":\"date\",\"value\":\"2026-03-08\"},{\"type\":\"future_value\",\"value\":{\"z\":1}}]}\"#\n    )\n    XCTAssertThrowsError(\n      try HealthMdQueryCanonicalSerializer.data(\n        for: HealthMdQueryValue.quantity(value: .nan, unit: \"x\")))\n    XCTAssertThrowsError(\n      try HealthMdQueryCanonicalSerializer.data(\n        for: HealthMdQueryValue.duration(seconds: .infinity)))\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testCanonicalDateRoundTripPreservesSubmillisecondBytesAndDigests",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 32,
      "end_line": 61,
      "symbol": "testCanonicalDateRoundTripPreservesSubmillisecondBytesAndDigests",
      "sha256": "9507df8243e34b50baa43a38129314cd142eecb286cfbbde5a999684ee57efa6",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "9507df8243e34b50baa43a38129314cd142eecb286cfbbde5a999684ee57efa6",
      "raw_utf8": "  func testCanonicalDateRoundTripPreservesSubmillisecondBytesAndDigests() throws {\n    let dates = [\n      Date(timeIntervalSince1970: 1_700_000_000.123456789),\n      Date(timeIntervalSince1970: 1_700_000_000.0000002),\n      Date(timeIntervalSince1970: -0.123456789),\n    ]\n\n    for date in dates {\n      let value = HealthMdQueryValue.timestamp(date)\n      let encoded = try HealthMdQueryCanonicalSerializer.data(for: value)\n      let decoded = try HealthMdQueryCanonicalSerializer.decode(\n        HealthMdQueryValue.self,\n        from: encoded\n      )\n      let reencoded = try HealthMdQueryCanonicalSerializer.data(for: decoded)\n\n      XCTAssertEqual(decoded, value)\n      XCTAssertEqual(reencoded, encoded)\n      XCTAssertEqual(\n        HealthMdQueryCanonicalSerializer.sha256(data: reencoded),\n        HealthMdQueryCanonicalSerializer.sha256(data: encoded)\n      )\n    }\n\n    XCTAssertTrue(\n      String(decoding: try HealthMdQueryCanonicalSerializer.data(for: dates[0]), as: UTF8.self)\n        .contains(\".123456717Z\")\n    )\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testCanonicalDateDecoderRejectsNoncanonicalTimestamps",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 62,
      "end_line": 77,
      "symbol": "testCanonicalDateDecoderRejectsNoncanonicalTimestamps",
      "sha256": "3b710f1aa630b3ce6f970be90acd4b863ba22956ffff9af8a9145ae4846dfeac",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "3b710f1aa630b3ce6f970be90acd4b863ba22956ffff9af8a9145ae4846dfeac",
      "raw_utf8": "  func testCanonicalDateDecoderRejectsNoncanonicalTimestamps() throws {\n    for timestamp in [\n      \"2023-11-14T22:13:20.123Z\",\n      \"2023-11-14T22:13:20.123456789+00:00\",\n      \"2023-11-14t22:13:20.123456789z\",\n      \"2023-02-29T22:13:20.123456789Z\",\n      \"2023-11-14T22:13:20.999999999Z\",\n    ] {\n      let payload = Data(#\"{\"type\":\"timestamp\",\"value\":\"\\#(timestamp)\"}\"#.utf8)\n      XCTAssertThrowsError(\n        try HealthMdQueryCanonicalSerializer.decode(HealthMdQueryValue.self, from: payload),\n        timestamp\n      )\n    }\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testDirectScopeSelectorsRejectAmbiguousDuplicateAndUnknownFields",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 78,
      "end_line": 133,
      "symbol": "testDirectScopeSelectorsRejectAmbiguousDuplicateAndUnknownFields",
      "sha256": "a0514d681ed882a500ab1bf3619a343967ae4d2d9586d43a0f72d89f83308262",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "a0514d681ed882a500ab1bf3619a343967ae4d2d9586d43a0f72d89f83308262",
      "raw_utf8": "  func testDirectScopeSelectorsRejectAmbiguousDuplicateAndUnknownFields() throws {\n    let decoder = JSONDecoder()\n    for json in [\n      #\"{\"type\":\"all_available\",\"metric_ids\":[\"steps\"]}\"#,\n      #\"{\"type\":\"explicit\",\"metric_ids\":[\"steps\",\"steps\"]}\"#,\n      #\"{\"type\":\"explicit\",\"metric_ids\":[\"steps\"],\"profile\":\"removed\"}\"#,\n    ] {\n      XCTAssertThrowsError(\n        try decoder.decode(\n          HealthMdMetricSelection.self,\n          from: Data(json.utf8)\n        ))\n    }\n    for json in [\n      #\"{\"type\":\"all_available\",\"source_ids\":[\"apple_health\"]}\"#,\n      #\"{\"type\":\"explicit\",\"source_ids\":[\"apple_health\",\"apple_health\"]}\"#,\n      #\"{\"type\":\"explicit\",\"provider_ids\":[\"oura\",\"oura\"]}\"#,\n      #\"{\"type\":\"explicit\",\"source_ids\":[],\"credential\":\"removed\"}\"#,\n    ] {\n      XCTAssertThrowsError(\n        try decoder.decode(\n          HealthMdSourceSelection.self,\n          from: Data(json.utf8)\n        ))\n    }\n    for json in [\n      #\"{\"type\":\"all_available\",\"range\":{\"start_date\":\"2026-01-01\",\"end_date\":\"2026-01-02\"}}\"#,\n      #\"{\"type\":\"exact\",\"range\":{\"start_date\":\"2026-01-01\",\"end_date\":\"2026-01-02\",\"extra\":true}}\"#,\n    ] {\n      XCTAssertThrowsError(\n        try decoder.decode(\n          HealthMdDateSelection.self,\n          from: Data(json.utf8)\n        ))\n    }\n    for json in [\n      #\"{\"type\":\"metric_series\",\"extra\":true}\"#,\n      #\"{\"type\":\"evidence_listing\"}\"#,\n      #\"{\"type\":\"sleep_session_listing\",\"window\":{\"duration_seconds\":3600,\"extra\":true}}\"#,\n      #\"{\"type\":\"period_comparison\",\"first\":{\"start_date\":\"2026-01-01\",\"end_date\":\"2026-01-02\"},\"second\":{\"start_date\":\"2026-01-03\",\"end_date\":\"2026-01-04\"},\"aggregations\":[]}\"#,\n      #\"{\"type\":\"period_comparison\",\"first\":{\"start_date\":\"2026-01-01\",\"end_date\":\"2026-01-02\"},\"second\":{\"start_date\":\"2026-01-03\",\"end_date\":\"2026-01-04\"},\"aggregations\":[{\"metric_id\":\"steps\",\"kind\":\"sum\"},{\"metric_id\":\"steps\",\"kind\":\"average\"}]}\"#,\n      #\"{\"type\":\"period_comparison\",\"first\":{\"start_date\":\"2026-01-01\",\"end_date\":\"2026-01-02\"},\"second\":{\"start_date\":\"2026-01-03\",\"end_date\":\"2026-01-04\"},\"aggregations\":[{\"metric_id\":\"steps\",\"kind\":\"sum\",\"extra\":true}]}\"#,\n    ] {\n      XCTAssertThrowsError(\n        try decoder.decode(\n          HealthMdQueryOperation.self,\n          from: Data(json.utf8)\n        ))\n    }\n    XCTAssertThrowsError(\n      try decoder.decode(\n        HealthMdPageControls.self,\n        from: Data(#\"{\"max_items\":10,\"max_bytes\":1000,\"extra\":true}\"#.utf8)\n      ))\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testCoverageAndSourcesRemainBoundedWithExplicitTruncationReceipts",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 322,
      "end_line": 357,
      "symbol": "testCoverageAndSourcesRemainBoundedWithExplicitTruncationReceipts",
      "sha256": "61417c4dec02515b275f4d3520107f66e3dec6543da4345ce8986f015f679df8",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "61417c4dec02515b275f4d3520107f66e3dec6543da4345ce8986f015f679df8",
      "raw_utf8": "  func testCoverageAndSourcesRemainBoundedWithExplicitTruncationReceipts() throws {\n    var missing: [HealthMdMissingInterval] = []\n    for index in 0..<100 {\n      let date = String(format: \"2026-%02d-%02d\", index / 28 + 1, index % 28 + 1)\n      missing.append(\n        HealthMdMissingInterval(\n          range: .init(startDate: date, endDate: date),\n          status: .notSynchronized\n        ))\n    }\n    let coverage = HealthMdCoverage(\n      requestedRange: nil,\n      availableRange: nil,\n      status: .partial,\n      daysConsidered: 100,\n      daysWithValues: 0,\n      missing: missing\n    )\n    let sources = (0..<100).map { index in\n      HealthMdSourceDescriptor(\n        schema: \"healthmd.health_data\", schemaVersion: 7, digest: String(format: \"%064x\", index))\n    }\n    let response = HealthMdQueryResponse(\n      items: [], packet: nil, coverage: coverage, sources: sources, evidence: [],\n      nextCursor: nil, limitations: []\n    )\n\n    XCTAssertEqual(response.coverage.missing.count, 64)\n    XCTAssertEqual(response.coverage.missingIntervalCount, 100)\n    XCTAssertEqual(response.coverage.missingTruncated, true)\n    XCTAssertEqual(response.sources.count, 64)\n    XCTAssertTrue(response.limitations.contains { $0.code == \"coverage_intervals_truncated\" })\n    XCTAssertTrue(response.limitations.contains { $0.code == \"source_descriptors_truncated\" })\n    XCTAssertLessThan(try HealthMdQueryCanonicalSerializer.data(for: response).count, 64 * 1_024)\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testCursorCompletenessTamperingAndQueryBinding",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 373,
      "end_line": 416,
      "symbol": "testCursorCompletenessTamperingAndQueryBinding",
      "sha256": "48b56412a728319796bd8771f5fffccc718b4efd80e16822c9daeaac3567c731",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "48b56412a728319796bd8771f5fffccc718b4efd80e16822c9daeaac3567c731",
      "raw_utf8": "  func testCursorCompletenessTamperingAndQueryBinding() throws {\n    let evaluator = try HealthMdQueryEvaluator(\n      days: [day(\"2026-01-01\", metrics: [metric(\"a\", id: \"1\"), metric(\"b\", id: \"2\")])],\n      cursorKey: cursorKey)\n    let request = HealthMdQueryRequest(\n      metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries,\n      page: .init(maxItems: 1, maxBytes: 10_000))\n    let first = try evaluator.evaluate(request)\n    let cursor = try XCTUnwrap(first.nextCursor)\n    let second = try evaluator.evaluate(\n      .init(\n        metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries,\n        page: .init(maxItems: 1, maxBytes: 10_000, cursor: cursor)))\n    XCTAssertEqual(second.items.count, 1)\n    var tampered = cursor\n    tampered.replaceSubrange(\n      tampered.index(before: tampered.endIndex)..., with: tampered.last == \"A\" ? \"B\" : \"A\")\n    XCTAssertThrowsError(\n      try evaluator.evaluate(\n        .init(\n          metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries,\n          page: .init(maxItems: 1, maxBytes: 10_000, cursor: tampered))))\n    XCTAssertThrowsError(\n      try evaluator.evaluate(\n        .init(\n          metrics: .explicit([\"a\"]), dates: .allAvailable, operation: .metricSeries,\n          page: .init(maxItems: 1, maxBytes: 10_000, cursor: cursor))))\n    let otherPeer = try HealthMdQueryEvaluator(\n      days: [day(\"2026-01-01\", metrics: [metric(\"a\", id: \"1\"), metric(\"b\", id: \"2\")])],\n      cursorKey: cursorKey,\n      cursorBinding: \"other-paired-installation\"\n    )\n    XCTAssertThrowsError(\n      try otherPeer.evaluate(\n        .init(\n          metrics: .allAvailable,\n          dates: .allAvailable,\n          operation: .metricSeries,\n          page: .init(maxItems: 1, maxBytes: 10_000, cursor: cursor)\n        )))\n  }\n\n  #if os(iOS)\n    @MainActor\n",
      "current_equals_historical": true
    },
    {
      "id": "testMissingnessAndCompleteEmptyRemainDistinctFromZero",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 426,
      "end_line": 458,
      "symbol": "testMissingnessAndCompleteEmptyRemainDistinctFromZero",
      "sha256": "cc7cec99129510b6143f76807bff35fb19741cd3ad0d7264a795257ea81ed6f2",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "cc7cec99129510b6143f76807bff35fb19741cd3ad0d7264a795257ea81ed6f2",
      "raw_utf8": "  func testMissingnessAndCompleteEmptyRemainDistinctFromZero() throws {\n    let unavailable: [HealthMdAvailabilityStatus] = [\n      .partial, .unsupported, .skipped, .cancelled, .notRequested, .legacyUnavailable, .redacted,\n      .notSynchronized,\n    ]\n    let metrics = unavailable.enumerated().map {\n      metric(\"m\\($0.offset)\", id: \"x\\($0.offset)\", value: nil, status: $0.element)\n    }\n    let evaluator = try HealthMdQueryEvaluator(\n      days: [day(\"2026-02-01\", metrics: metrics), day(\"2026-02-02\", status: .completeEmpty)],\n      cursorKey: cursorKey)\n    let response = try evaluator.evaluate(\n      .init(\n        metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries,\n        page: .init(maxItems: 100, maxBytes: 100_000)))\n    let points = response.items.compactMap {\n      if case .metric(let value) = $0 { return value }\n      return nil\n    }\n    XCTAssertEqual(points.count, unavailable.count)\n    XCTAssertTrue(points.allSatisfy { $0.value == nil })\n    XCTAssertEqual(Set(points.map(\\.status)), Set(unavailable))\n    XCTAssertEqual(response.coverage.status, .partial)\n\n    let emptyEvaluator = try HealthMdQueryEvaluator(\n      days: [day(\"2026-02-02\", status: .completeEmpty)], cursorKey: cursorKey)\n    let empty = try emptyEvaluator.evaluate(\n      .init(metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries))\n    XCTAssertTrue(empty.items.isEmpty)\n    XCTAssertEqual(empty.coverage.status, .completeEmpty)\n    XCTAssertEqual(empty.coverage.daysWithValues, 0)\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testCountComparisonsRemainExactAndRejectOverflow",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 659,
      "end_line": 718,
      "symbol": "testCountComparisonsRemainExactAndRejectOverflow",
      "sha256": "99ad8e1e32ee8aced9c59395a8c8085e9cf72c7119d20887c79ac07809379d37",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "99ad8e1e32ee8aced9c59395a8c8085e9cf72c7119d20887c79ac07809379d37",
      "raw_utf8": "  func testCountComparisonsRemainExactAndRejectOverflow() throws {\n    let evaluator = try HealthMdQueryEvaluator(\n      days: [\n        day(\n          \"2026-06-01\",\n          metrics: [metric(\"steps\", id: \"large-a\", value: .count(9_007_199_254_740_992))]),\n        day(\n          \"2026-06-02\",\n          metrics: [metric(\"steps\", id: \"large-b\", value: .count(9_007_199_254_740_993))]),\n        day(\"2026-06-03\", metrics: [metric(\"steps\", id: \"minimum\", value: .count(.min))]),\n        day(\"2026-06-04\", metrics: [metric(\"steps\", id: \"maximum\", value: .count(.max))]),\n        day(\"2026-06-05\", metrics: [metric(\"steps\", id: \"maximum-2\", value: .count(.max))]),\n      ], cursorKey: cursorKey)\n    let exact = try evaluator.evaluate(\n      .init(\n        metrics: .explicit([\"steps\"]),\n        dates: .allAvailable,\n        operation: .periodComparison(\n          first: .init(startDate: \"2026-06-01\", endDate: \"2026-06-01\"),\n          second: .init(startDate: \"2026-06-02\", endDate: \"2026-06-02\"),\n          aggregations: [.init(metricID: \"steps\", kind: .latest)]\n        )\n      ))\n    guard case .comparison(let comparison) = try XCTUnwrap(exact.items.first) else {\n      return XCTFail(\"Missing comparison\")\n    }\n    XCTAssertEqual(comparison.absoluteChange, .count(1))\n    XCTAssertEqual(comparison.direction, .increased)\n\n    let largeAverage = try evaluator.evaluate(\n      .init(\n        metrics: .explicit([\"steps\"]),\n        dates: .allAvailable,\n        operation: .periodComparison(\n          first: .init(startDate: \"2026-06-04\", endDate: \"2026-06-05\"),\n          second: .init(startDate: \"2026-06-04\", endDate: \"2026-06-05\"),\n          aggregations: [.init(metricID: \"steps\", kind: .average)]\n        )\n      ))\n    guard case .comparison(let average) = try XCTUnwrap(largeAverage.items.first) else {\n      return XCTFail(\"Missing average comparison\")\n    }\n    XCTAssertEqual(average.firstValue, .count(.max))\n\n    XCTAssertThrowsError(\n      try evaluator.evaluate(\n        .init(\n          metrics: .explicit([\"steps\"]),\n          dates: .allAvailable,\n          operation: .periodComparison(\n            first: .init(startDate: \"2026-06-03\", endDate: \"2026-06-03\"),\n            second: .init(startDate: \"2026-06-04\", endDate: \"2026-06-04\"),\n            aggregations: [.init(metricID: \"steps\", kind: .latest)]\n          )\n        ))\n    ) { error in\n      XCTAssertEqual(error as? HealthMdQueryContractError, .nonFiniteNumber)\n    }\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testAllMetricsAndFullHistoryAreCompletelyReachableThroughCursorPaging",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 172,
      "end_line": 202,
      "symbol": "testAllMetricsAndFullHistoryAreCompletelyReachableThroughCursorPaging",
      "sha256": "5e3390bd09c1fae0f04168dd9c02f8b49a5a0a15e42f9f061380dac19abd15b2",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "5e3390bd09c1fae0f04168dd9c02f8b49a5a0a15e42f9f061380dac19abd15b2",
      "raw_utf8": "  func testAllMetricsAndFullHistoryAreCompletelyReachableThroughCursorPaging() throws {\n    let days = (0..<20).map { index in\n      day(\n        \"2026-01-\\(String(format: \"%02d\", index + 1))\",\n        metrics: [\n          metric(\"dynamic_\\(index % 3)\", id: \"m-\\(index)\", value: .count(Int64(index)))\n        ])\n    }\n    let evaluator = try HealthMdQueryEvaluator(days: days, cursorKey: cursorKey)\n    var cursor: String?\n    var items: [HealthMdQueryItem] = []\n    repeat {\n      let response = try evaluator.evaluate(\n        .init(\n          metrics: .allAvailable, dates: .allAvailable, operation: .metricSeries,\n          page: .init(maxItems: 3, maxBytes: 700, cursor: cursor)\n        ))\n      XCTAssertLessThanOrEqual(response.items.count, 3)\n      items.append(contentsOf: response.items)\n      cursor = response.nextCursor\n    } while cursor != nil\n    XCTAssertEqual(items.count, 20)\n    let points: [HealthMdMetricPoint] = items.compactMap { item in\n      guard case .metric(let value) = item else { return nil }\n      return value\n    }\n    XCTAssertEqual(Set(points.map(\\.metricID)), Set([\"dynamic_0\", \"dynamic_1\", \"dynamic_2\"]))\n    XCTAssertEqual(points.first?.ownerDate, \"2026-01-01\")\n    XCTAssertEqual(points.last?.ownerDate, \"2026-01-20\")\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testCompleteResponseStaysWithinPageByteBudgetForLongAlternatingCoverage",
      "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
      "start_line": 266,
      "end_line": 321,
      "symbol": "testCompleteResponseStaysWithinPageByteBudgetForLongAlternatingCoverage",
      "sha256": "c326cc1759a2dc08ca634ce6106b86ed671bc9dd0fa4514f7ba2bd73750b9c70",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "c326cc1759a2dc08ca634ce6106b86ed671bc9dd0fa4514f7ba2bd73750b9c70",
      "raw_utf8": "  func testCompleteResponseStaysWithinPageByteBudgetForLongAlternatingCoverage() throws {\n    var calendar = Calendar(identifier: .gregorian)\n    calendar.timeZone = TimeZone(secondsFromGMT: 0)!\n    let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!\n    let formatter = DateFormatter()\n    formatter.calendar = calendar\n    formatter.timeZone = calendar.timeZone\n    formatter.dateFormat = \"yyyy-MM-dd\"\n    var days: [HealthMdCompactContextDay] = []\n    for index in 0..<1_000 {\n      let ownerDate = formatter.string(\n        from: calendar.date(byAdding: .day, value: index, to: start)!)\n      let available = index.isMultiple(of: 2)\n      days.append(\n        day(\n          ownerDate,\n          status: available ? .available : .partial,\n          metrics: [\n            metric(\n              \"steps\",\n              id: \"steps-\\(index)\",\n              value: available ? .count(Int64(index)) : nil,\n              status: available ? .available : .failed\n            )\n          ]\n        ))\n    }\n    let evaluator = try HealthMdQueryEvaluator(days: days, cursorKey: cursorKey)\n    let maximumBytes = 64 * 1_024\n    let response = try evaluator.evaluateBounded(\n      .init(\n        metrics: .explicit([\"steps\"]),\n        dates: .allAvailable,\n        operation: .metricSeries,\n        page: .init(maxItems: 1_000, maxBytes: maximumBytes)\n      ))\n\n    XCTAssertLessThanOrEqual(\n      try HealthMdQueryCanonicalSerializer.data(for: response).count,\n      maximumBytes\n    )\n    let cursor = try XCTUnwrap(response.nextCursor)\n    let continuation = try evaluator.evaluateBounded(\n      .init(\n        metrics: .explicit([\"steps\"]),\n        dates: .allAvailable,\n        operation: .metricSeries,\n        page: .init(maxItems: 1_000, maxBytes: maximumBytes, cursor: cursor)\n      ))\n    XCTAssertLessThanOrEqual(\n      try HealthMdQueryCanonicalSerializer.data(for: continuation).count,\n      maximumBytes\n    )\n    XCTAssertFalse(continuation.items.isEmpty)\n  }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testProviderOnlyProjectionEmitsProviderEvidenceWithoutApplePlaceholders",
      "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
      "start_line": 133,
      "end_line": 180,
      "symbol": "testProviderOnlyProjectionEmitsProviderEvidenceWithoutApplePlaceholders",
      "sha256": "bb725f1438c0b24e4b1be9b92bd2e50395bb99d603ed3807c46fe0fa35c95bd8",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "bb725f1438c0b24e4b1be9b92bd2e50395bb99d603ed3807c46fe0fa35c95bd8",
      "raw_utf8": "    func testProviderOnlyProjectionEmitsProviderEvidenceWithoutApplePlaceholders() throws {\n        let start = iso(\"2026-02-03T00:00:00Z\")\n        let provider = ExternalDailyRecord(\n            provider: .whoop,\n            date: \"2026-02-03\",\n            fetchedAt: start,\n            payloads: [\n                ExternalProviderPayload(\n                    name: \"sleep\",\n                    endpoint: \"https://api.prod.whoop.com/developer/v2/activity/sleep\",\n                    statusCode: 200,\n                    fetchedAt: start,\n                    data: .object([\"score\": .number(87)])\n                )\n            ]\n        )\n\n        let day = try HealthMdQueryContextProjector.project(\n            HealthData(\n                date: start,\n                timeContext: .init(calendarTimeZoneIdentifier: \"UTC\"),\n                healthKitRecordCaptureStatus: .notRequested\n            ),\n            externalProviderRecords: [provider],\n            options: .init(enabledMetricIDs: [\"sleep_total\"], includesAppleHealth: false)\n        )\n\n        XCTAssertTrue(day.metrics.isEmpty)\n        XCTAssertTrue(day.workouts.isEmpty)\n        XCTAssertTrue(day.sleepSessions.isEmpty)\n        XCTAssertEqual(day.status, .available)\n        XCTAssertTrue(day.evidence.contains {\n            $0.reference.providerID == \"whoop\"\n                && $0.reference.sourceID == HealthMdEvidenceSourceIDs.providerNative\n        })\n        XCTAssertTrue(day.evidence.contains {\n            $0.metricIDs == [\"sleep_total\"]\n                && $0.reference.locator == .queryManifest(\n                    ownerDate: \"2026-02-03\",\n                    identifier: \"provider_daily_fetch:whoop:sleep_total\"\n                )\n        })\n        XCTAssertFalse(day.evidence.contains {\n            $0.reference.sourceID == HealthMdEvidenceSourceIDs.appleHealth\n                || $0.reference.sourceID == HealthMdEvidenceSourceIDs.healthMdSummary\n        })\n    }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testPreservesDSTOwnershipAndCreatesResolvableCanonicalEvidenceAndWorkout",
      "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
      "start_line": 181,
      "end_line": 283,
      "symbol": "testPreservesDSTOwnershipAndCreatesResolvableCanonicalEvidenceAndWorkout",
      "sha256": "941d253a307a32e19fb63848fe8de4840ea40bfb1a8ee236611aced0382818e0",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "941d253a307a32e19fb63848fe8de4840ea40bfb1a8ee236611aced0382818e0",
      "raw_utf8": "    func testPreservesDSTOwnershipAndCreatesResolvableCanonicalEvidenceAndWorkout() throws {\n        let start = iso(\"2026-03-08T08:00:00Z\")\n        let end = iso(\"2026-03-09T07:00:00Z\")\n        let workoutUUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000101\")!\n        let quantityUUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000102\")!\n        let record = HealthKitRecord(\n            originalUUID: quantityUUID,\n            objectTypeIdentifier: \"HKQuantityTypeIdentifierStepCount\",\n            recordKind: .quantity,\n            selectedMetricIDs: [\"steps\"],\n            includedBecause: .selectedMetric,\n            startDate: start.addingTimeInterval(3_600),\n            endDate: start.addingTimeInterval(3_601),\n            sourceRevision: sourceRevision,\n            payload: .quantity(.init(value: 3, unit: \"count\"))\n        )\n        let workoutRecord = HealthKitRecord(\n            originalUUID: workoutUUID,\n            objectTypeIdentifier: \"HKWorkoutTypeIdentifier\",\n            recordKind: .workout,\n            selectedMetricIDs: [\"workouts\"],\n            includedBecause: .selectedMetric,\n            startDate: start.addingTimeInterval(7_200),\n            endDate: start.addingTimeInterval(9_000),\n            sourceRevision: sourceRevision,\n            payload: .structured(kind: \"workout\", fields: [:])\n        )\n        let external = HealthKitExternalRecord(\n            externalIdentifier: \"activity-summary:2026-03-08\",\n            externalIdentityKind: .activitySummaryDateComponents,\n            objectTypeIdentifier: \"HKActivitySummaryTypeIdentifier\",\n            recordKind: .activitySummary,\n            selectedMetricIDs: [\"activity_summary\"],\n            fields: [\"active_energy\": .floatingPoint(500)]\n        )\n        let archive = makeArchive(\n            start: start,\n            end: end,\n            timeZone: \"America/Los_Angeles\",\n            records: [record, workoutRecord],\n            externalRecords: [external],\n            queryManifest: .init(results: [query(\"steps-query\", metricID: \"steps\", status: .success, count: 1, start: start, end: end)]),\n            warnings: [.init(code: \"sample_warning\", message: \"A source warning.\", metricIDs: [\"steps\"], recordUUIDs: [quantityUUID])]\n        )\n        let workout = WorkoutData(\n            id: workoutUUID,\n            sourceUUID: workoutUUID,\n            workoutType: .running,\n            healthKitActivityType: \"running\",\n            healthKitActivityTypeRawValue: 37,\n            startTime: start.addingTimeInterval(7_200),\n            actualEndDate: start.addingTimeInterval(9_000),\n            isIndoor: false,\n            duration: 1_700,\n            calories: 200,\n            distance: 5_000,\n            avgHeartRate: 145\n        )\n        let data = HealthData(\n            date: start,\n            timeContext: .init(calendarTimeZoneIdentifier: \"America/Los_Angeles\"),\n            activity: ActivityData(steps: 3),\n            workouts: [workout],\n            partialFailures: [.init(date: start, dataType: \"steps\", dateRangeDescription: \"day\", errorDescription: \"Sibling detail failed\")],\n            healthKitRecordArchive: archive\n        )\n\n        let day = try HealthMdQueryContextProjector.project(data, options: .init(enabledMetricIDs: [\"steps\", \"workouts\", \"activity_summary\"]))\n        XCTAssertEqual(day.ownerDate, \"2026-03-08\")\n        XCTAssertEqual(day.intervalStart, start)\n        XCTAssertEqual(day.intervalEnd, end)\n        XCTAssertEqual(day.intervalEnd.timeIntervalSince(day.intervalStart), 23 * 3_600)\n        XCTAssertEqual(day.calendarTimeZone, \"America/Los_Angeles\")\n        XCTAssertEqual(day.workouts.count, 1)\n        XCTAssertEqual(day.workouts[0].workoutID, workoutUUID.uuidString.lowercased())\n        XCTAssertEqual(day.workouts[0].start, workout.startTime)\n        XCTAssertEqual(day.workouts[0].end, workout.actualEndDate)\n        XCTAssertEqual(day.workouts[0].details[\"distance\"], .quantity(value: 5_000, unit: \"m\"))\n\n        XCTAssertTrue(day.evidence.contains { if case .canonicalUUID(_, let uuid) = $0.reference.locator { return uuid == quantityUUID.uuidString.lowercased() }; return false })\n        XCTAssertTrue(day.evidence.contains { if case .externalIdentity(_, let id) = $0.reference.locator { return id == external.externalIdentifier }; return false })\n        XCTAssertTrue(day.evidence.contains { if case .queryManifest(_, let id) = $0.reference.locator { return id == \"steps-query\" }; return false })\n        XCTAssertTrue(day.evidence.contains { if case .warning(_, let code) = $0.reference.locator { return code == \"sample_warning\" }; return false })\n        XCTAssertTrue(day.evidence.contains { if case .partialFailure = $0.reference.locator { return true }; return false })\n        XCTAssertTrue(HealthMdEvidenceResolver.allResolve(day.evidence.map(\\.reference), in: [day]))\n        let stepsEvidenceIDs = Set(metric(\"steps\", in: day).evidenceIDs)\n        let stepsEvidence = day.evidence.filter {\n            stepsEvidenceIDs.contains($0.reference.evidenceID)\n        }\n        XCTAssertFalse(stepsEvidence.isEmpty)\n        XCTAssertTrue(stepsEvidence.allSatisfy {\n            $0.reference.sourceID == HealthMdEvidenceSourceIDs.healthMdSummary\n        })\n        XCTAssertTrue(day.evidence.contains {\n            $0.metricIDs.contains(\"steps\")\n                && $0.reference.sourceID == HealthMdEvidenceSourceIDs.appleHealth\n                && !stepsEvidenceIDs.contains($0.reference.evidenceID)\n        })\n        let workoutEvidence = Set(day.workouts[0].evidenceIDs)\n        XCTAssertFalse(workoutEvidence.isEmpty)\n        XCTAssertTrue(workoutEvidence.isSubset(of: Set(day.evidence.map { $0.reference.evidenceID })))\n    }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testProjectionIsPermutationInvariantAndRetainsUnknownArchiveMetrics",
      "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
      "start_line": 284,
      "end_line": 321,
      "symbol": "testProjectionIsPermutationInvariantAndRetainsUnknownArchiveMetrics",
      "sha256": "e6188976330102fe049f9df89d4b98f25938004a381127855178c81fbbda7d85",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "e6188976330102fe049f9df89d4b98f25938004a381127855178c81fbbda7d85",
      "raw_utf8": "    func testProjectionIsPermutationInvariantAndRetainsUnknownArchiveMetrics() throws {\n        let start = iso(\"2026-04-01T00:00:00Z\")\n        let end = iso(\"2026-04-02T00:00:00Z\")\n        let firstUUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000201\")!\n        let secondUUID = UUID(uuidString: \"00000000-0000-0000-0000-000000000202\")!\n        let records = [\n            HealthKitRecord(\n                originalUUID: firstUUID,\n                objectTypeIdentifier: \"HKFutureTypeIdentifier\",\n                recordKind: .other(\"future\"),\n                selectedMetricIDs: [\"future_archive_metric\"],\n                includedBecause: .selectedMetric,\n                startDate: start.addingTimeInterval(20),\n                endDate: start.addingTimeInterval(30),\n                sourceRevision: sourceRevision,\n                payload: .unknown(kind: \"future_payload\", fields: [\"answer\": .signedInteger(42)])\n            ),\n            HealthKitRecord(\n                originalUUID: secondUUID,\n                objectTypeIdentifier: \"HKQuantityTypeIdentifierStepCount\",\n                recordKind: .quantity,\n                selectedMetricIDs: [\"steps\"],\n                includedBecause: .selectedMetric,\n                startDate: start.addingTimeInterval(10),\n                endDate: start.addingTimeInterval(11),\n                sourceRevision: sourceRevision,\n                payload: .quantity(.init(value: 2, unit: \"count\"))\n            )\n        ]\n        let workouts = [\n            WorkoutData(id: UUID(uuidString: \"00000000-0000-0000-0000-000000000211\"), workoutType: .walking, startTime: start.addingTimeInterval(100), duration: 60, calories: 3, distance: 20),\n            WorkoutData(id: UUID(uuidString: \"00000000-0000-0000-0000-000000000212\"), workoutType: .running, startTime: start.addingTimeInterval(200), duration: 120, calories: 9, distance: 100)\n        ]\n        let providerPayloads = [\n            ExternalProviderPayload(name: \"z\", endpoint: \"https://example.test/z\", statusCode: 200, fetchedAt: start, data: .object([\"value\": .number(2)])),\n            ExternalProviderPayload(name: \"a\", endpoint: \"https://example.test/a\", statusCode: 200, fetchedAt: start, data: .array([]))\n        ]\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testEveryCurrentCatalogMetricIsAccountedForAndDailyExportSchemaRemainsV8",
      "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
      "start_line": 433,
      "end_line": 451,
      "symbol": "testEveryCurrentCatalogMetricIsAccountedForAndDailyExportSchemaRemainsV8",
      "sha256": "de29f3907b56ed5a5818b9c9f1cb83f53bcb2d92dfaa380cac6fbefbf777c77b",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "de29f3907b56ed5a5818b9c9f1cb83f53bcb2d92dfaa380cac6fbefbf777c77b",
      "raw_utf8": "    func testEveryCurrentCatalogMetricIsAccountedForAndDailyExportSchemaRemainsV8() throws {\n        let start = iso(\"2026-05-01T00:00:00Z\")\n        let ids = Set(HealthMetrics.all.map(\\.id))\n        let day = try HealthMdQueryContextProjector.project(\n            HealthData(date: start, timeContext: .init(calendarTimeZoneIdentifier: \"UTC\"), healthKitRecordCaptureStatus: .notRequested),\n            options: .init(enabledMetricIDs: ids)\n        )\n        XCTAssertEqual(Set(day.metrics.map(\\.metricID)), ids)\n        XCTAssertEqual(HealthMdExportSchema.version, 8)\n        XCTAssertEqual(day.source.schemaVersion, 8)\n        XCTAssertEqual(day.schemaVersion, 1)\n    }\n\n    // MARK: Helpers\n\n    private var sourceRevision: HealthKitSourceRevision {\n        .init(name: \"Tests\", bundleIdentifier: \"tech.isolated.healthmd.tests\")\n    }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testCursorTamperingAndMutationFailClosedAndSingleOversizeItemFails",
      "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
      "start_line": 111,
      "end_line": 187,
      "symbol": "testCursorTamperingAndMutationFailClosedAndSingleOversizeItemFails",
      "sha256": "56ee7ee6d21e7d600a82d18f0135227f119a04ff5f41178f0eaf90ad6a37c4af",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "56ee7ee6d21e7d600a82d18f0135227f119a04ff5f41178f0eaf90ad6a37c4af",
      "raw_utf8": "    func testCursorTamperingAndMutationFailClosedAndSingleOversizeItemFails() async throws {\n        let (store, executor) = try makeSystem(metrics: [\"steps\"], allowsEvidenceValues: true)\n        let evidence = contextEvidence(\n            id: \"large\",\n            day: \"2026-01-01\",\n            sourceID: HealthMdEvidenceSourceIDs.appleHealth,\n            value: .string(String(repeating: \"x\", count: 2_000)),\n            metricIDs: [\"steps\"]\n        )\n        try await store.upsert(day(\n            \"2026-01-01\",\n            metrics: [metric(\"steps\", id: \"a\"), metric(\"steps\", id: \"b\")],\n            evidence: [evidence]\n        ))\n        let firstRequest = HealthMdQueryRequest(\n            metrics: .allAvailable,\n            dates: .allAvailable,\n            operation: .metricSeries,\n            page: .init(maxItems: 1, maxBytes: 50_000)\n        )\n        let first = try await executor.execute(firstRequest, detailLevel: .summary)\n        let cursor = try XCTUnwrap(first.nextCursor)\n\n        var tampered = cursor\n        let index = tampered.index(tampered.startIndex, offsetBy: tampered.count / 2)\n        tampered.replaceSubrange(index...index, with: tampered[index] == \"A\" ? \"B\" : \"A\")\n        await XCTAssertThrowsQueryError(.invalidCursor) {\n            _ = try await executor.execute(\n                HealthMdQueryRequest(\n                    metrics: .allAvailable,\n                    dates: .allAvailable,\n                    operation: .metricSeries,\n                    page: .init(maxItems: 1, maxBytes: 50_000, cursor: tampered)\n                ),\n                detailLevel: .summary\n            )\n        }\n\n        await XCTAssertThrowsQueryError(.cursorDoesNotMatchQuery) {\n            _ = try await executor.execute(\n                HealthMdQueryRequest(\n                    metrics: .allAvailable,\n                    dates: .allAvailable,\n                    operation: .metricSeries,\n                    page: .init(maxItems: 1, maxBytes: 50_000, cursor: cursor)\n                ),\n                detailLevel: .summary,\n                evidenceScope: .init(allowedMetricIDs: [])\n            )\n        }\n\n        try await store.upsert(day(\"2026-01-02\", metrics: [metric(\"steps\", id: \"c\")]))\n        await XCTAssertThrowsQueryError(.staleCursor) {\n            _ = try await executor.execute(\n                HealthMdQueryRequest(\n                    metrics: .allAvailable,\n                    dates: .allAvailable,\n                    operation: .metricSeries,\n                    page: .init(maxItems: 1, maxBytes: 50_000, cursor: cursor)\n                ),\n                detailLevel: .summary\n            )\n        }\n\n        await XCTAssertThrowsQueryError(.singleItemExceedsPageBytes) {\n            _ = try await executor.execute(\n                HealthMdQueryRequest(\n                    metrics: .allAvailable,\n                    dates: .exact(.init(startDate: \"2026-01-01\", endDate: \"2026-01-01\")),\n                    operation: .sourceRecordListing,\n                    page: .init(maxItems: 10, maxBytes: 200)\n                ),\n                detailLevel: .lossless\n            )\n        }\n    }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testAppleAndProviderEvidenceValuesArePagedAndFilterableWithBackwardSourceDefault",
      "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
      "start_line": 188,
      "end_line": 252,
      "symbol": "testAppleAndProviderEvidenceValuesArePagedAndFilterableWithBackwardSourceDefault",
      "sha256": "4a10d67091ac1bde700a47b3d5ace6155e0dbc51ff8156e1e39b0b49b88df9e8",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "4a10d67091ac1bde700a47b3d5ace6155e0dbc51ff8156e1e39b0b49b88df9e8",
      "raw_utf8": "    func testAppleAndProviderEvidenceValuesArePagedAndFilterableWithBackwardSourceDefault() async throws {\n        let (store, executor) = try makeSystem(metrics: [\"steps\"], allowsEvidenceValues: true)\n        let source = HealthMdSourceDescriptor(schema: \"healthmd.health_data\", schemaVersion: 7, digest: \"source\")\n        let apple = HealthMdContextEvidence(\n            reference: .init(\n                evidenceID: \"apple\",\n                locator: .canonicalUUID(ownerDate: \"2026-02-01\", uuid: \"00000000-0000-0000-0000-000000000001\"),\n                source: source,\n                sourceID: HealthMdEvidenceSourceIDs.appleHealth\n            ),\n            value: .unknown(type: \"canonical_healthkit_record\", value: .object([\"uuid\": .string(\"00000000-0000-0000-0000-000000000001\")])),\n            metricIDs: [\"steps\"]\n        )\n        let provider = HealthMdContextEvidence(\n            reference: .init(\n                evidenceID: \"provider\",\n                locator: .externalIdentity(ownerDate: \"2026-02-01\", identifier: \"provider:oura:record\"),\n                source: source,\n                sourceID: HealthMdEvidenceSourceIDs.providerNative,\n                providerID: \"oura\"\n            ),\n            value: .unknown(type: \"external_provider_payload\", value: .object([\"provider\": .string(\"oura\"), \"raw\": .integer(7)]))\n        )\n        try await store.upsert(day(\"2026-02-01\", evidence: [apple, provider]))\n\n        let all = try await collectItems(\n            executor: executor,\n            metrics: .allAvailable,\n            dates: .allAvailable,\n            operation: .sourceRecordListing,\n            maxItems: 1,\n            detailLevel: .lossless\n        )\n        let values = all.compactMap { item -> HealthMdContextEvidence? in\n            guard case .evidence(let evidence) = item else { return nil }\n            return evidence\n        }\n        XCTAssertEqual(values.map { $0.reference.evidenceID }, [\"apple\", \"provider\"])\n        XCTAssertNotNil(values[0].value)\n        XCTAssertNotNil(values[1].value)\n\n        let providerOnly = try await executor.execute(\n            HealthMdQueryRequest(\n                metrics: .allAvailable,\n                sources: .explicit(sourceIDs: [], providerIDs: [\"oura\"]),\n                dates: .allAvailable,\n                operation: .sourceRecordListing,\n                page: .init(maxItems: 10, maxBytes: 100_000)\n            ),\n            detailLevel: .lossless\n        )\n        XCTAssertEqual(providerOnly.items.count, 1)\n        guard case .evidence(let selected) = try XCTUnwrap(providerOnly.items.first) else {\n            return XCTFail(\"Expected provider evidence\")\n        }\n        XCTAssertEqual(selected.reference.providerID, \"oura\")\n\n        let legacyJSON = #\"{\"schema\":\"healthmd.query_request\",\"schema_version\":1,\"metrics\":{\"type\":\"all_available\"},\"dates\":{\"type\":\"all_available\"},\"operation\":{\"type\":\"metric_series\"},\"page\":{\"max_items\":10,\"max_bytes\":10000}}\"#\n        let decoded = try HealthMdQueryCanonicalSerializer.decode(\n            HealthMdQueryRequest.self,\n            from: Data(legacyJSON.utf8)\n        )\n        XCTAssertEqual(decoded.sources, .allAvailable)\n    }\n\n",
      "current_equals_historical": true
    },
    {
      "id": "testComparisonPacketAndMissingnessRemainExactAndNeutral",
      "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
      "start_line": 253,
      "end_line": 312,
      "symbol": "testComparisonPacketAndMissingnessRemainExactAndNeutral",
      "sha256": "af7a2949f9192c19ae95bb9d65bb242267bc712b1c674123425ec782ebd0d8a4",
      "hash_method": "raw UTF8 assigned source range including LF",
      "current_sha256": "af7a2949f9192c19ae95bb9d65bb242267bc712b1c674123425ec782ebd0d8a4",
      "raw_utf8": "    func testComparisonPacketAndMissingnessRemainExactAndNeutral() async throws {\n        let (store, executor) = try makeSystem(metrics: [\"steps\"])\n        try await store.upsert([\n            day(\"2026-03-01\", metrics: [metric(\"steps\", id: \"zero\", value: .count(0))]),\n            day(\"2026-03-02\", metrics: [metric(\"steps\", id: \"five\", value: .count(5))]),\n            day(\"2026-03-03\", status: .partial, metrics: [metric(\"steps\", id: \"missing\", value: nil, status: .partial)])\n        ])\n\n        let comparisonResponse = try await executor.execute(\n            HealthMdQueryRequest(\n                metrics: .explicit([\"steps\"]),\n                dates: .allAvailable,\n                operation: .periodComparison(\n                    first: .init(startDate: \"2026-03-01\", endDate: \"2026-03-01\"),\n                    second: .init(startDate: \"2026-03-02\", endDate: \"2026-03-02\"),\n                    aggregations: [.init(metricID: \"steps\", kind: .sum)]\n                )\n            ),\n            detailLevel: .summary\n        )\n        guard case .comparison(let comparison) = try XCTUnwrap(comparisonResponse.items.first) else {\n            return XCTFail(\"Expected comparison\")\n        }\n        XCTAssertEqual(comparison.firstValue, .count(0))\n        XCTAssertEqual(comparison.secondValue, .count(5))\n        XCTAssertNil(comparison.percentChange)\n        XCTAssertEqual(comparison.direction, .increased)\n\n        let packetResponse = try await executor.execute(\n            HealthMdQueryRequest(\n                metrics: .explicit([\"steps\"]),\n                dates: .allAvailable,\n                operation: .derivePacket(kind: .doctorVisit, detailIDs: []),\n                page: .init(maxItems: 10, maxBytes: 100_000)\n            ),\n            detailLevel: .summary\n        )\n        let packet = try XCTUnwrap(packetResponse.packet)\n        XCTAssertEqual(packet.facts.count, 2)\n        XCTAssertTrue(packet.limitations.contains { $0.code == \"factual_observations_only\" })\n        XCTAssertFalse(try HealthMdQueryCanonicalSerializer.string(for: packet).lowercased().contains(\"you should\"))\n\n        let series = try await executor.execute(\n            HealthMdQueryRequest(\n                metrics: .explicit([\"steps\"]),\n                dates: .allAvailable,\n                operation: .metricSeries,\n                page: .init(maxItems: 10, maxBytes: 100_000)\n            ),\n            detailLevel: .summary\n        )\n        let missing = series.items.compactMap { item -> HealthMdMetricPoint? in\n            guard case .metric(let point) = item, point.ownerDate == \"2026-03-03\" else { return nil }\n            return point\n        }\n        XCTAssertEqual(missing.first?.value, nil)\n        XCTAssertEqual(missing.first?.status, .partial)\n        XCTAssertEqual(series.coverage.missing.last?.status, .partial)\n    }\n\n",
      "current_equals_historical": true
    }
  ],
  "inventory_pointers": [
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/query_authority",
      "canonical_value_sha256": "7abf19f7e04622f7a04c9dcc6fa8c742f9001c001b1287ebb47f91a628d80316",
      "current_canonical_sha256": "7abf19f7e04622f7a04c9dcc6fa8c742f9001c001b1287ebb47f91a628d80316",
      "current_value": {
        "current_evaluator": "Swift; Rust operations only normalize, transport, validate receipt and traverse pages",
        "native_sources": [
          {
            "path": "apps/apple/HealthMd/Shared/Query/QueryContracts.swift",
            "sha256": "72f56754e04653b9262394932b9baaac0468cc96a8b498dd11c35be989f00118",
            "bytes": 54211
          },
          {
            "path": "apps/apple/HealthMd/Shared/Query/QueryTypedValue.swift",
            "sha256": "1658be7cf1db8ad530356eebf2e986a501ef223f57ffc2571a9540817e57916f",
            "bytes": 8432
          },
          {
            "path": "apps/apple/HealthMd/Shared/Query/QueryCanonicalSerializer.swift",
            "sha256": "b6b2de86e7cfd0c03c7105ae65750b23189ab7f163e4823ee4d983bcc0445feb",
            "bytes": 6998
          },
          {
            "path": "apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift",
            "sha256": "54b13797c7f94170aae77d33bd89a27fdb8a9b3e6c03fce796df2eefd01141ee",
            "bytes": 60997
          },
          {
            "path": "apps/apple/HealthMd/Shared/Query/HealthMdQueryContextProjector.swift",
            "sha256": "2e4de29fd916b7b313f6c3c9840ff1cee6dce1460186db2891282401b00eb79f",
            "bytes": 45870
          },
          {
            "path": "apps/apple/HealthMd/Shared/Query/HealthMdSleepSessionQuery.swift",
            "sha256": "d87ad3432c4c8d23ee6760fae56cca57d8d7992c3eeaff04792853d2a6ef62eb",
            "bytes": 25564
          },
          {
            "path": "apps/apple/HealthMd/iOS/IPhoneDirectQueryCoordinator.swift",
            "sha256": "c8853d6146182271df6a36c6f69144e60351f6b0149fc726819d82f5a97e9655",
            "bytes": 23373
          },
          {
            "path": "apps/apple/HealthMd/macOS/Managers/EncryptedHealthContextQueryExecutor.swift",
            "sha256": "4ed7a29568a34952760ac7bb81ade5034b2230ae89dd2845bb1ca30f8944ce68",
            "bytes": 109333
          }
        ],
        "query_types": [
          "metric_series",
          "period_comparison",
          "source_record_listing",
          "sleep_session_listing",
          "workout_sleep_alignment",
          "workout_listing",
          "coverage",
          "derive_packet"
        ],
        "typed_values": [
          "quantity finite binary64+unit",
          "duration finite seconds",
          "count Int64",
          "string",
          "category",
          "boolean",
          "timestamp canonical Date",
          "date ISO civil date",
          "array",
          "unknown tagged JSON payload retained (Int64/UInt64 finite Double)"
        ],
        "selectors": "explicit unique sorted metric IDs/all_available; source/provider scope independent; omitted sources defaults all_available. Direct iPhone allows apple_health/healthmd_summary with no provider IDs; Mac context can include provider_native/evidence. Exact dates/calendar ownership and selected comparison periods; unknown selectors/fields/duplicates/unauthorized records fail closed.",
        "semantics": "Explicit aggregation sum/average/minimum/maximum/latest/count/duration_sum; checked count sums/deltas, no binary64 roundtrip or saturation. Missing/complete-empty/zero stay distinct. Scope/evidence source locator must resolve; packet ID excludes volatile metadata. Sleep boundaries, naps, overlap-safe authorized totals, fixed window and nearest workout alignment preserve factual exclusions.",
        "cursor": {
          "authority": "apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift",
          "payload_fields": [
            "offset",
            "query",
            "dataset",
            "binding"
          ],
          "request_hash_fields": [
            "schema",
            "schema_version",
            "metrics",
            "sources",
            "dates",
            "operation",
            "max_items",
            "max_bytes"
          ],
          "format": "base64url(no padding) canonical envelope {payload:base64url(canonical payload),mac:lowercase hex HMAC-SHA256(payloadString UTF8)}",
          "binding": "query fingerprint excludes opaque cursor and transport UUID; dataset sorted ownerDate/source digest hashed; trusted installation binding; constant-time MAC and query/dataset/binding match",
          "lifecycle": "iPhone-protected32-byte key; frozen foreground paging snapshot10min inactivity; terminal/background clears; ordinary authenticated closure may reconnect same trust; mismatched/stale cursor fails instead of recapture. Whole response byte budget re-bounds metadata/items and emits explicit continuation. Single oversize item fails."
        },
        "independent_expectations": "Native test_cases below are pre-rewrite synthetic source assertions. Rust/export fixtures do not qualify evaluator precision/coverage/context/evidence. Extract separately reviewed serialized expected corpus from those cases before replacing Swift; no extraction or product tests executed here.",
        "independent_case_references": [
          {
            "path": "apps/android/direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/InteroperabilityTest.kt",
            "case_id": "canonicalRequestAndFingerprintMatchRust",
            "status": "not_run"
          },
          {
            "path": "apps/android/direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/InteroperabilityTest.kt",
            "case_id": "defaultCollectionsMatchRustCanonicalEnvelopeBytes",
            "status": "not_run"
          },
          {
            "path": "apps/android/direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/PacketPollingTest.kt",
            "case_id": "timeoutDuringSplitLengthPreservesPacketFraming",
            "status": "not_run"
          },
          {
            "path": "apps/android/direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/ProfilePolicyInteropTest.kt",
            "case_id": "canonicalRequestBytesMatchTheFrozenVector",
            "status": "not_run"
          },
          {
            "path": "apps/android/direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/SharedPairingV3InteropTest.kt",
            "case_id": "sharedPairingCryptoAndQrMatchCanonicalFixture",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Models/IPhoneDirectFileJournalTests.swift",
            "case_id": "testPinnedDirectRangePermitsFailedEdgeDaysWithReducedCoverage",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Models/IPhoneDirectFileJournalTests.swift",
            "case_id": "testCanonicalDirectSelectionCannotProduceProviderSidecars",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
            "case_id": "testProviderOnlyProjectionEmitsProviderEvidenceWithoutApplePlaceholders",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
            "case_id": "testPreservesDSTOwnershipAndCreatesResolvableCanonicalEvidenceAndWorkout",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
            "case_id": "testProjectionIsPermutationInvariantAndRetainsUnknownArchiveMetrics",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
            "case_id": "testProjectsSleepSessionsAndDecodesLegacyContextWithoutSessionField",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/HealthMdQueryContextProjectorTests.swift",
            "case_id": "testEveryCurrentCatalogMetricIsAccountedForAndDailyExportSchemaRemainsV8",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testCanonicalBytesAreStableAndRejectNonFiniteValues",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testCanonicalDateRoundTripPreservesSubmillisecondBytesAndDigests",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testCanonicalDateDecoderRejectsNoncanonicalTimestamps",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testPacketIDIsPermutationInvariantAndExcludesVolatileMetadata",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testAllMetricsAndFullHistoryAreCompletelyReachableThroughCursorPaging",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testCompleteResponseStaysWithinPageByteBudgetForLongAlternatingCoverage",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testCoverageAndSourcesRemainBoundedWithExplicitTruncationReceipts",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testCursorCompletenessTamperingAndQueryBinding",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testMissingnessAndCompleteEmptyRemainDistinctFromZero",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testComparisonDoesNotDoubleCountDuplicateObservationsOrWorkouts",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testComparisonRejectsEmptyDuplicateAndUnselectedAggregationScopes",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testEvidenceResolutionRequiresMatchingLocatorAndSource",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testMetricSeriesUsesCompactSummaryEvidenceForDenseLosslessDays",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testCountComparisonsRemainExactAndRejectOverflow",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testSleepSessionsUseStableBoundariesClassificationAndFixedWindow",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testSleepSessionTotalsAreAuthorizedAndOverlapSafe",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testWorkoutSleepAlignmentIsDeterministicFactualAndExplicitAboutExclusions",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/Query/QueryFoundationTests.swift",
            "case_id": "testPacketDerivationsEnforceScopeAndUseMedicalSafetyWording",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/SharedCore/AppleDirectProtocolAuthorityTests.swift",
            "case_id": "testShadowReturnsNativeAndRecordsOnlyHealthFreeCounts",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
            "case_id": "testMetricSeriesPrefersSummaryEvidenceWhileRawRecordsRemainPageable",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
            "case_id": "testCursorTamperingAndMutationFailClosedAndSingleOversizeItemFails",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
            "case_id": "testAppleAndProviderEvidenceValuesArePagedAndFilterableWithBackwardSourceDefault",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
            "case_id": "testComparisonPacketAndMissingnessRemainExactAndNeutral",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
            "case_id": "testEncryptedWorkoutSleepAlignmentUsesNearestSessionsAndActivityFilter",
            "status": "not_run"
          },
          {
            "path": "apps/apple/HealthMdTests/macOS/EncryptedHealthContextQueryExecutorTests.swift",
            "case_id": "testSleepSessionPagingUsesAdjacentDaysAndFailsClosedWithoutSleepScope",
            "status": "not_run"
          },
          {
            "path": "apps/apple/Packages/HealthMdCoreRust/Tests/HealthMdCoreRustTests/ProtocolFoundationTests.swift",
            "case_id": "testCanonicalV1V2FixturesAndProtocolInfoCrossPackagedBoundary",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-cli/src/main.rs",
            "case_id": "canonical_pointer_validation_rejects_ambiguous_escapes",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-cli/src/main.rs",
            "case_id": "generic_help_routes_typed_queries_and_shows_the_sleep_shape",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-cli/src/mcp/mod.rs",
            "case_id": "every_query_operation_has_cli_and_mcp_canonical_parity",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-cli/src/output.rs",
            "case_id": "generic_results_keep_missingness_and_nested_records_visible",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/credentials.rs",
            "case_id": "helper_protocol_allows_only_the_fixed_trust_account_and_shapes",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/file_receiver.rs",
            "case_id": "windows_canonical_destination_round_trips_through_policy",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/job.rs",
            "case_id": "durable_counters_and_messages_are_bounded",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/limits.rs",
            "case_id": "lifecycle_accounting_reserves_four_bounded_copies_per_input_job",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/limits.rs",
            "case_id": "retained_job_count_is_shared_across_protocol_versions",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/packet.rs",
            "case_id": "packet_round_trips_across_split_tcp_stream",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/packet.rs",
            "case_id": "zero_length_packet_fails_before_allocation",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/raw_receiver.rs",
            "case_id": "all_empty_corpus_preserves_v1_scalar_and_records_no_evidenced_versions",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/raw_receiver.rs",
            "case_id": "empty_day_and_retained_v8_day_report_only_the_evidenced_version",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/raw_receiver.rs",
            "case_id": "homogeneous_v7_and_v8_corpora_report_evidenced_versions_in_json_and_jsonl",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-client/src/v2_job.rs",
            "case_id": "android_durable_counters_and_messages_are_bounded",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-mcp/src/application.rs",
            "case_id": "remote_profile_traverses_cursors_without_exposing_local_operations",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-mcp/src/application.rs",
            "case_id": "resumed_traversal_never_resubmits_a_nonadvancing_cursor",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-mcp/src/application.rs",
            "case_id": "backend_wait_cancellation_uses_the_canonical_local_outcome",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-operations/src/normalize.rs",
            "case_id": "generated_and_extract_selection_share_canonical_rules",
            "status": "not_run"
          },
          {
            "path": "apps/cli/crates/healthmd-operations/src/registry.rs",
            "case_id": "typed_sleep_query_adds_required_metrics_and_lossless_scope",
            "status": "not_run"
          },
          {
            "path": "packages/healthmd-core-rust/crates/healthmd-protocol/tests/profile_policy.rs",
            "case_id": "canonical_selection_still_round_trips_alongside_profile",
            "status": "not_run"
          },
          {
            "path": "packages/healthmd-core-rust/crates/healthmd-protocol/tests/shared_pairing_v3_vectors.rs",
            "case_id": "shared_pairing_v3_matches_canonical_fixture",
            "status": "not_run"
          },
          {
            "path": "packages/healthmd-core-rust/crates/healthmd-protocol/tests/swift_v1_vectors.rs",
            "case_id": "rust_matches_swift_pairing_proof_and_decodes_packet",
            "status": "not_run"
          },
          {
            "path": "packages/healthmd-core-rust/crates/healthmd-protocol/tests/swift_v1_vectors.rs",
            "case_id": "rust_canonical_request_and_fingerprint_match_swift",
            "status": "not_run"
          },
          {
            "path": "packages/healthmd-core-rust/crates/healthmd-protocol/tests/v2_profile_vectors.rs",
            "case_id": "canonical_request_json_matches_frozen_vector",
            "status": "not_run"
          }
        ]
      },
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/schemas/query_request",
      "canonical_value_sha256": "d8eea63e55601c9666af65f1efd68b2219bce990e7bb953cc2949de9d3d7185d",
      "current_canonical_sha256": "d8eea63e55601c9666af65f1efd68b2219bce990e7bb953cc2949de9d3d7185d",
      "current_value": {
        "id": "healthmd.query_request",
        "version": 1
      },
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/schemas/query_response",
      "canonical_value_sha256": "6f8f029a425dbb028c16abdb537a578ce3325e8faebdac289dae4420c883fc75",
      "current_canonical_sha256": "6f8f029a425dbb028c16abdb537a578ce3325e8faebdac289dae4420c883fc75",
      "current_value": {
        "id": "healthmd.query_response",
        "version": 1
      },
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/schemas/context_day",
      "canonical_value_sha256": "c7a23719f7c5cee831790948278aa6e3af5d5ddbd8cf4c14bf0705e52428397b",
      "current_canonical_sha256": "c7a23719f7c5cee831790948278aa6e3af5d5ddbd8cf4c14bf0705e52428397b",
      "current_value": {
        "id": "healthmd.query_context_day",
        "version": 1
      },
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/catalog/full_operation_ids",
      "canonical_value_sha256": "392dbbf249139f896a7cb654285de0138faa8d0e7581ec0c00334e3cd0db0bb5",
      "current_canonical_sha256": "392dbbf249139f896a7cb654285de0138faa8d0e7581ec0c00334e3cd0db0bb5",
      "current_value": [
        "healthmd_status",
        "healthmd_doctor",
        "healthmd_capabilities",
        "healthmd_metrics",
        "healthmd_metric_chart",
        "healthmd_sleep_sessions",
        "healthmd_training_alignment",
        "healthmd_workouts",
        "healthmd_coverage",
        "healthmd_compare_periods",
        "healthmd_training_evidence",
        "healthmd_query",
        "healthmd_evidence_packet",
        "healthmd_pairing_start",
        "healthmd_pairing_status",
        "healthmd_export_files",
        "healthmd_export_raw",
        "healthmd_raw_artifact_read",
        "healthmd_export_job_status",
        "healthmd_export_job_resume",
        "healthmd_export_job_cancel"
      ],
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/catalog/read_only_operation_ids",
      "canonical_value_sha256": "ba3c662e55c5027c430b5c5b0d325cb879a6ceea5061327fb0393de12f279e13",
      "current_canonical_sha256": "ba3c662e55c5027c430b5c5b0d325cb879a6ceea5061327fb0393de12f279e13",
      "current_value": [
        "healthmd_status",
        "healthmd_doctor",
        "healthmd_capabilities",
        "healthmd_metrics",
        "healthmd_metric_chart",
        "healthmd_sleep_sessions",
        "healthmd_training_alignment",
        "healthmd_workouts",
        "healthmd_coverage",
        "healthmd_compare_periods",
        "healthmd_training_evidence",
        "healthmd_query",
        "healthmd_evidence_packet"
      ],
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/cli/commands",
      "canonical_value_sha256": "f113c0d8824c58a8e2e40bc154b7e3e82659c160cc514a276153ab70e1ddf13a",
      "current_canonical_sha256": "f113c0d8824c58a8e2e40bc154b7e3e82659c160cc514a276153ab70e1ddf13a",
      "current_value": [
        "status",
        "export",
        "extract",
        "query",
        "resume",
        "cancel",
        "direct pair",
        "direct devices",
        "direct unpair",
        "direct reset-trust",
        "mcp serve",
        "mcp serve-read-only",
        "mcp schema",
        "setup codex"
      ],
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/platforms/direct_typed_query",
      "canonical_value_sha256": "80c98ee375688d0b3b327400004c36f82bb6bd9a8c87d6ddf84b077d0b5be7dd",
      "current_canonical_sha256": "80c98ee375688d0b3b327400004c36f82bb6bd9a8c87d6ddf84b077d0b5be7dd",
      "current_value": {
        "classification": "apple_only",
        "apple": "foreground v3 shipped source",
        "android_current": "unavailable; no query capability or evaluator advertised",
        "android_future": {
          "classification": "planned",
          "target": "K05/O02 separately scoped Health Connect authorized native query capability, independent fixtures and host qualification before advertise/support; no existing implementation date inferred"
        }
      },
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/bounds/aggregate_traversal",
      "canonical_value_sha256": "7fe06c5455b71a75766500eac4f743ca5d61f6b5e1e248b52856d36f9702fa78",
      "current_canonical_sha256": "7fe06c5455b71a75766500eac4f743ca5d61f6b5e1e248b52856d36f9702fa78",
      "current_value": {
        "maximum_bytes": 2097152,
        "maximum_pages": 4096,
        "page_reserve_bytes": 16384,
        "authority": "apps/cli/crates/healthmd-operations/src/limits.rs and apps/cli/crates/healthmd-operations/src/service.rs",
        "overflow": "first oversized page errors; later page excluded and receipt returns requested_cursor with maximum_aggregate_bytes; maximum_pages yields explicit continuation; cursor cycles rejected"
      },
      "same_historical": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "json_pointer": "/bounds/native_query",
      "canonical_value_sha256": "e8a6a3e2e4a185327300c51fb5c5cc237b218c12dd2ead5776c61b6b5a8b0345",
      "current_canonical_sha256": "e8a6a3e2e4a185327300c51fb5c5cc237b218c12dd2ead5776c61b6b5a8b0345",
      "current_value": {
        "days": 366000,
        "compact_context_bytes": 67108864,
        "page_items": 1000,
        "page_bytes": 1048576,
        "default_page_items": 250,
        "default_page_bytes": 262144,
        "missing_intervals": 64,
        "source_descriptors": 64,
        "capture_inactivity_seconds": 600,
        "authority": [
          "apps/apple/HealthMd/iOS/IPhoneDirectQueryCoordinator.swift",
          "apps/apple/HealthMd/Shared/Query/QueryContracts.swift"
        ],
        "single_active_query_or_export": true,
        "limitation_entries": 64
      },
      "same_historical": true
    }
  ],
  "preserved_packet_minima": [
    {
      "case_id": "query-count-beyond-binary64",
      "input": {
        "typed_value": {
          "type": "count",
          "value_decimal": "9007199254740993"
        }
      },
      "expected": {
        "class": "i64",
        "decimal": "9007199254740993",
        "round_via_Double": false
      },
      "source_basis": "typed-tags",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    },
    {
      "case_id": "query-count-max",
      "input": {
        "type": "count",
        "value_decimal": "9223372036854775807"
      },
      "expected": {
        "decimal": "9223372036854775807",
        "saturate": false
      },
      "source_basis": "typed-tags",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    },
    {
      "case_id": "query-finite-quantity",
      "input": {
        "type": "quantity",
        "binary64_bits": "4029000000000000",
        "unit": "km"
      },
      "expected": {
        "value": "12.5",
        "unit": "km",
        "count_conversion": false
      },
      "source_basis": "testCanonicalBytesAreStableAndRejectNonFiniteValues",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    },
    {
      "case_id": "query-nonfinite-rejected",
      "input": {
        "type": "duration",
        "binary64_bits": "7ff0000000000000"
      },
      "expected": {
        "accepted": false,
        "safe_code": "non_finite_number",
        "provider_echo": false
      },
      "source_basis": "typed-tags",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    },
    {
      "case_id": "query-unknown-tag",
      "input": {
        "type": "future_value",
        "value": {
          "z": 1
        }
      },
      "expected": {
        "tag": "future_value",
        "payload": {
          "z": 1
        },
        "schema_inference": false
      },
      "source_basis": "typed-json",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    },
    {
      "case_id": "query-unknown-absent-null",
      "input": {
        "inputs": [
          {
            "type": "future_value"
          },
          {
            "type": "future_value",
            "value": null
          }
        ]
      },
      "expected": {
        "decoded_payload": null,
        "encoded_value_field": false
      },
      "source_basis": "typed-tags decodeIfPresent/encodeIfPresent",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    },
    {
      "case_id": "query-native-date-source-rounding",
      "input": {
        "native_Date_Unix_construction": "1700000000.123456789"
      },
      "expected": {
        "canonical_fraction": "123456717",
        "not_claimed_exact_nanoseconds": true
      },
      "source_basis": "testCanonicalDateRoundTripPreservesSubmillisecondBytesAndDigests",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    },
    {
      "case_id": "query-timestamp-short-fraction",
      "input": {
        "typed_value": {
          "type": "timestamp",
          "value": "2023-11-14T22:13:20.123Z"
        }
      },
      "expected": {
        "accepted": false,
        "source_profile": "canonical nine-digit UTC plus Foundation Date reproduce-byte check"
      },
      "source_basis": "testCanonicalDateDecoderRejectsNoncanonicalTimestamps",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    },
    {
      "case_id": "query-value-unknown-field-profile",
      "input": {
        "type": "count",
        "value": 3,
        "extra": "synthetic"
      },
      "expected": {
        "decoded_count": 3,
        "extra_retained": false,
        "request_profile_strictness_inherited": false
      },
      "source_basis": "typed-tags has no rejectUnknownKeys",
      "proof_class": "planning",
      "execution": "literal_minimum_not_executed; full closed typed Stage1 corpus independently reviewed before code"
    }
  ],
  "minima_mapping": {
    "query-count-beyond-binary64": "count-beyond-binary64",
    "query-count-max": "count-i64-max",
    "query-finite-quantity": "quantity-12-point-5",
    "query-nonfinite-rejected": "nonfinite-bit-input",
    "query-unknown-tag": "unknown-object",
    "query-unknown-absent-null": [
      "unknown-value-absent",
      "unknown-value-null"
    ],
    "query-native-date-source-rounding": "timestamp-native-rounded-construction-witness",
    "query-timestamp-short-fraction": "timestamp-native-reject-1",
    "query-value-unknown-field-profile": "ignored-known-extra"
  },
  "private_bounds": {
    "raw_UTF8_bytes": 65536,
    "decoded_each_key_or_string_UTF8_bytes": 8192,
    "container_depth": 32,
    "nodes_total": 4096,
    "numeric_raw_token_bytes": 1024,
    "factory_busy_operations": 1,
    "meaning": "Unmeasured private per-value batch controls only, never public export/history limits; callers retain supported history and page through owning query operation. Reject overbudget before profile callback/property effects. Global counters include ignored subtree syntax/key scanning, never reset on recursive unknowns."
  },
  "grammar": {
    "source_tagged_decode": "Required type string; quantity finite Double value + required unit string; duration finite Double seconds; count Int64 value; string String value; category identifier String required, display/raw_value optional or null; boolean Bool; timestamp Foundation canonical Date decoder; date String unvalidated; array typed values; unknown tag optional HealthMdJSONValue value (missing/null -> nil), tag preserved. Unknown CodingKeys ignored, unlike strict request selectors.",
    "encoding": "Native query sortedKeys/withoutEscapingSlashes; known tags encode only their fields; optional category/unknown fields omit nil; array order preserved; object native canonical ordering requires profile fixture, no serde equivalence. Canonical number spellings via pure source profile capability, no duplicated numeric renderer. Exact observed native encodings in native_source_witness override generic serde for matching native operands only.",
    "primitive_input": "utf8 primitive string or utf8_hex lowercase exact bytes; strict UTF8/UTF16 scalar validity and full JSON syntax consumption before native profile/host callbacks; raw lexemes retained, no JSON.parse numeric coercion. Unknown property containers bounded scan but ignored key payload never becomes materialized evidence/title.",
    "profile_reconciliation": "Accepted exact-number/parser/value/serializer are serde profiles. Reuse only proven canonical integer/finite-bit/structural intersections; native numeric lexical class/duplicate/special RawValue differ or unproven. Ordinary local internal codec composition is not new package export.",
    "unknown_number_order": "Bool -> Int64 -> UInt64 -> finiteDouble -> String -> array -> object, exact original source precedence. Negative/nonintegral/overflow/1.0/1e0/-0 decisions delegated only to captured source-profile capability with independently frozen primary witness; absent witness fixed native_profile_unavailable, never falsely assert native reject. Reviewed exact numeric operands now admitted as limited synthetic source-profile witnesses; no general lexical grammar extrapolation.",
    "native_timestamps": "Nine fraction digits UTC reproduce via actual Foundation Date; source .123456789 constructor canonical .123456717 and rejected .999999999 preserved. Civil date branch has no calendar validator. No rational Unix nanoseconds/timezone arithmetic fabricated."
  },
  "ownership_lifetime": {
    "allocation": "No native/resource allocation or release in this pure value boundary: allocation/release/ACK counters always0. Owned graph token issuance is finite synchronous private registration, not host resource. If profile capability acquires native resources, its own scoped bracket/partial cleanup/ACK is required separately; this factory cannot claim that capability.",
    "capture": "Capture original Scope, Current.check and NativeProfile methods once; replayable close signal before callbacks. Unknown/foreign tokens including Proxy checked samefactory WeakSet before any properties/coercion. Exact issued native token bound frame/slot/factory/callback, never profile JSON flags.",
    "reads": "Each lazy read/encode execution requires own request+own exact value+same callback context; invalid/expired returns null zero Current/property traps. Fresh captured Current per execution; after await check original Scope/poison/membership/exact identity/context/callback before primitive materialization without intervening yield.",
    "callback": "Inner ensuring expires actual callback/native issuer immediately on its Effect exit BEFORE postcurrent; outerbackstop covers interruption. Fresh Scope/Layer/replaced methods cannot revive. Original close while pending Current signals cancellation, no join from same finalizer; caller completion reflects actual pending owned callback cleanup, not invented physical ACK.",
    "priority": "Pending external interruption survives; original Scope close wins over fixed profile/current failure or defect after callback; fixed sanitation no provider payload echo. Pure no resource cleanup does not claim native cancellation/transactions."
  },
  "case_count": 128,
  "cases": [
    {
      "case_id": "quantity-12-point-5",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"quantity\",\"value\":12.5,\"unit\":\"km\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "quantity",
          "bits": "4029000000000000",
          "unit": "km"
        },
        "canonical_utf8": "{\"type\":\"quantity\",\"unit\":\"km\",\"value\":12.5}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "testCanonicalBytesAreStableAndRejectNonFiniteValues exact full bytes"
    },
    {
      "case_id": "duration-60",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"duration\",\"seconds\":60}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "duration",
          "bits": "404e000000000000",
          "unit": "s"
        },
        "canonical_utf8": "{\"seconds\":60,\"type\":\"duration\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "same native exact canonical literal"
    },
    {
      "case_id": "count-three",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "count-beyond-binary64",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":9007199254740993}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "9007199254740993",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":9007199254740993}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact independently reviewed macOS source row count-exact; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "count-exact"
    },
    {
      "case_id": "count-i64-max",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":9223372036854775807}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "9223372036854775807",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":9223372036854775807}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact independently reviewed macOS source row count-max; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "count-max"
    },
    {
      "case_id": "count-i64-min",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":-9223372036854775808}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "-9223372036854775808",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":-9223372036854775808}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "count-zero",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":0}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "0",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":0}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "string-x",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"string\",\"value\":\"x\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "string",
          "value": "x"
        },
        "canonical_utf8": "{\"type\":\"string\",\"value\":\"x\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "string-controls",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"string\",\"value\":\"a\\n\\t\\\"\\\\/\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "string",
          "value": "a\n\t\"\\/"
        },
        "canonical_utf8": "{\"type\":\"string\",\"value\":\"a\\n\\t\\\"\\\\/\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "boolean-true",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"boolean\",\"value\":true}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "boolean",
          "value": true
        },
        "canonical_utf8": "{\"type\":\"boolean\",\"value\":true}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "boolean-false",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"boolean\",\"value\":false}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "boolean",
          "value": false
        },
        "canonical_utf8": "{\"type\":\"boolean\",\"value\":false}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "category-all-fields",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"category\",\"identifier\":\"asleep\",\"display\":\"Asleep\",\"raw_value\":2}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "category",
          "identifier": "asleep",
          "display": "Asleep",
          "raw_value": "2"
        },
        "canonical_utf8": "{\"display\":\"Asleep\",\"identifier\":\"asleep\",\"raw_value\":2,\"type\":\"category\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "native array test exact bytes"
    },
    {
      "case_id": "category-optional-absent",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"category\",\"identifier\":\"light\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "category",
          "identifier": "light",
          "display": null,
          "raw_value": null
        },
        "canonical_utf8": "{\"identifier\":\"light\",\"type\":\"category\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "category-optional-null",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"category\",\"identifier\":\"light\",\"display\":null,\"raw_value\":null}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "category",
          "identifier": "light",
          "display": null,
          "raw_value": null
        },
        "canonical_utf8": "{\"identifier\":\"light\",\"type\":\"category\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "date-civil-text",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"date\",\"value\":\"2026-03-08\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "date",
          "value": "2026-03-08"
        },
        "canonical_utf8": "{\"type\":\"date\",\"value\":\"2026-03-08\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "civil_calendar_validation_performed": false
      },
      "source_basis": "date branch is String, no canonical date validator here"
    },
    {
      "case_id": "date-not-calendar-validator",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"date\",\"value\":\"2026-02-30\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "date",
          "value": "2026-02-30"
        },
        "canonical_utf8": "{\"type\":\"date\",\"value\":\"2026-02-30\"}",
        "observed_reads": 1,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact independently reviewed macOS source row date-invalid-calendar-raw; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "date-invalid-calendar-raw"
    },
    {
      "case_id": "date-arbitrary-string-preserved",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"date\",\"value\":\"synthetic-civil-text\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "date",
          "value": "synthetic-civil-text"
        },
        "canonical_utf8": "{\"type\":\"date\",\"value\":\"synthetic-civil-text\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "civil_calendar_validation_performed": false
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "timestamp-native-eighth-second",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.125000000Z\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "timestamp",
          "native_profile": "foundation_Date_reproduce_bytes",
          "canonical": "2023-11-14T22:13:20.125000000Z",
          "exact_unix_nanoseconds_claimed": false
        },
        "canonical_utf8": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.125000000Z\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 0
      },
      "source_basis": "native exact array literal; Date basis remains native source, not epoch integer surrogate"
    },
    {
      "case_id": "timestamp-native-rounded-construction-witness",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456717Z\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "timestamp",
          "native_profile": "foundation_Date_reproduce_bytes",
          "canonical": "2023-11-14T22:13:20.123456717Z",
          "exact_unix_nanoseconds_claimed": false,
          "reference_bits": "41c58214400fcd6e",
          "unix_bits": "41d954fc4007e6b7"
        },
        "canonical_utf8": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456717Z\"}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact independently reviewed macOS source row timestamp-nine-representable; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "timestamp-nine-representable"
    },
    {
      "case_id": "array-empty",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"array\",\"value\":[]}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "array",
          "values": []
        },
        "canonical_utf8": "{\"type\":\"array\",\"value\":[]}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "array-order",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"array\",\"value\":[{\"type\":\"count\",\"value\":2},{\"type\":\"count\",\"value\":1}]}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "array",
          "values": [
            {
              "type": "count",
              "decimal": "2",
              "unit": "count"
            },
            {
              "type": "count",
              "decimal": "1",
              "unit": "count"
            }
          ]
        },
        "canonical_utf8": "{\"type\":\"array\",\"value\":[{\"type\":\"count\",\"value\":2},{\"type\":\"count\",\"value\":1}]}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 2,
        "native_canonical_number_calls": 2
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "unknown-object",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":{\"z\":1}}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "object",
            "entries": [
              [
                "z",
                {
                  "kind": "i64",
                  "decimal": "1"
                }
              ]
            ]
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":{\"z\":1}}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "native exact array test unknown payload"
    },
    {
      "case_id": "unknown-value-absent",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": null
        },
        "canonical_utf8": "{\"type\":\"future_value\"}",
        "observed_reads": 1,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact independently reviewed macOS source row unknown-absent; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "unknown-absent"
    },
    {
      "case_id": "unknown-value-null",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":null}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": null
        },
        "canonical_utf8": "{\"type\":\"future_value\"}",
        "observed_reads": 1,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact independently reviewed macOS source row unknown-null; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "unknown-null"
    },
    {
      "case_id": "unknown-bool",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":true}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "boolean",
            "value": true
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":true}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "HealthMdJSONValue decode Bool then Int64 then UInt64 then finiteDouble; canonical integer and nonintegral exact-half math witnesses; no full Foundation lexical equivalence"
    },
    {
      "case_id": "unknown-string",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":\"x\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "string",
            "value": "x"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":\"x\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "HealthMdJSONValue decode Bool then Int64 then UInt64 then finiteDouble; canonical integer and nonintegral exact-half math witnesses; no full Foundation lexical equivalence"
    },
    {
      "case_id": "unknown-i64-negative",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":-9223372036854775808}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "i64",
            "decimal": "-9223372036854775808"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":-9223372036854775808}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "HealthMdJSONValue decode Bool then Int64 then UInt64 then finiteDouble; canonical integer and nonintegral exact-half math witnesses; no full Foundation lexical equivalence"
    },
    {
      "case_id": "unknown-i64-max",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":9223372036854775807}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "i64",
            "decimal": "9223372036854775807"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":9223372036854775807}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "HealthMdJSONValue decode Bool then Int64 then UInt64 then finiteDouble; canonical integer and nonintegral exact-half math witnesses; no full Foundation lexical equivalence"
    },
    {
      "case_id": "unknown-u64-first",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":9223372036854775808}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "u64",
            "decimal": "9223372036854775808"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":9223372036854775808}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "HealthMdJSONValue decode Bool then Int64 then UInt64 then finiteDouble; canonical integer and nonintegral exact-half math witnesses; no full Foundation lexical equivalence"
    },
    {
      "case_id": "unknown-u64-max",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":18446744073709551615}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "u64",
            "decimal": "18446744073709551615"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":18446744073709551615}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "HealthMdJSONValue decode Bool then Int64 then UInt64 then finiteDouble; canonical integer and nonintegral exact-half math witnesses; no full Foundation lexical equivalence"
    },
    {
      "case_id": "unknown-finite-half",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":1.5}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "f64",
            "bits": "3ff8000000000000"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":1.5}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "HealthMdJSONValue decode Bool then Int64 then UInt64 then finiteDouble; canonical integer and nonintegral exact-half math witnesses; no full Foundation lexical equivalence"
    },
    {
      "case_id": "ignored-known-extra",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"extra\":{\"title\":\"excluded synthetic\"}}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "typed CodingKeys no rejectUnknownKeys; discard valid extra without title value materialization"
    },
    {
      "case_id": "known-tag-extra-fields-not-newtype",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"string\",\"value\":\"x\",\"unit\":\"km\",\"seconds\":4}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "string",
          "value": "x"
        },
        "canonical_utf8": "{\"type\":\"string\",\"value\":\"x\"}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0
      },
      "source_basis": "QueryTypedValue.swift Codable switch; native fixed integer/string witness"
    },
    {
      "case_id": "unknown-tag-known-name-shape",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_quantity\",\"value\":3,\"unit\":\"km\"}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_quantity",
          "value": {
            "kind": "i64",
            "decimal": "3"
          }
        },
        "canonical_utf8": "{\"type\":\"future_quantity\",\"value\":3}",
        "observed_reads": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1
      },
      "source_basis": "tag preserved; no shape schema inference"
    },
    {
      "case_id": "missing-type",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"value\":3}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "type-not-string",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":3,\"value\":3}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "count-overflow-positive",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":9223372036854775808}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_pipeline_observation": "native_rejected",
        "native_decoder_stage_error_not_inferred": true
      },
      "source_basis": "Exact independently reviewed macOS source row count-overflow; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "count-overflow"
    },
    {
      "case_id": "count-overflow-negative",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":-9223372036854775809}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "count-string",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":\"3\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "quantity-missing-unit",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"quantity\",\"value\":12.5}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "quantity-unit-null",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"quantity\",\"value\":12.5,\"unit\":null}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "duration-missing-seconds",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"duration\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "category-missing-identifier",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"category\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "category-raw-overflow",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"category\",\"identifier\":\"x\",\"raw_value\":9223372036854775808}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "string-null",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"string\",\"value\":null}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "boolean-number",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"boolean\",\"value\":1}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "date-number",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"date\",\"value\":0}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "array-unknown-element-shape",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"array\",\"value\":[3]}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "root-array",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "[]",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "trailing-json",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3} false",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "literal-NaN",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"quantity\",\"value\":NaN,\"unit\":\"x\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "lone-surrogate",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"string\",\"value\":\"\\ud800\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "timestamp-native-reject-1",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123Z\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_pipeline_observation": "native_rejected",
        "native_decoder_stage_error_not_inferred": true
      },
      "source_basis": "Exact independently reviewed macOS source row timestamp-short; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "timestamp-short"
    },
    {
      "case_id": "timestamp-native-reject-2",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456789+00:00\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact original testCanonicalDateDecoderRejectsNoncanonicalTimestamps literal"
    },
    {
      "case_id": "timestamp-native-reject-3",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"timestamp\",\"value\":\"2023-11-14t22:13:20.123456789z\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact original testCanonicalDateDecoderRejectsNoncanonicalTimestamps literal"
    },
    {
      "case_id": "timestamp-native-reject-4",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"timestamp\",\"value\":\"2023-02-29T22:13:20.123456789Z\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Exact original testCanonicalDateDecoderRejectsNoncanonicalTimestamps literal"
    },
    {
      "case_id": "timestamp-native-reject-5",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.999999999Z\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_pipeline_observation": "native_rejected",
        "native_decoder_stage_error_not_inferred": true
      },
      "source_basis": "Exact independently reviewed macOS source row timestamp-carry; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "timestamp-carry"
    },
    {
      "case_id": "unknown-proxy-input",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": {
          "driver_constructs": "unknown Proxy all traps throw"
        },
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "raw-invalid-UTF8",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8_hex",
        "payload": "c080",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "private-raw-budget-plus-one",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": {
          "recipe": "ascii_space_repeat",
          "repeat": 65537
        },
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "private-depth-plus-one",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": {
          "recipe": "nested_unknown_JSON_arrays",
          "array_depth": 32,
          "total_container_depth": 33
        },
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "private-nodes-plus-one",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": {
          "recipe": "unknown_array_nulls",
          "elements": 4094,
          "total_nodes": 4097
        },
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "private-string-bytes-plus-one",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": {
          "recipe": "typed_string",
          "repeat_ascii_x": 8193
        },
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Source tagged field type/range; private primitive bounds explicitly unmeasured"
    },
    {
      "case_id": "duplicate-type",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"type\":\"string\",\"value\":\"x\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "native_profile_unavailable",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Underlying Foundation JSONDecoder lexical conversion/duplicates/parse precedence lacks independently pinned OS witness. Private port returns unavailable pending evidence; NOT assertion native rejects/accepts. Generic serde special RawValue behavior not native authority."
    },
    {
      "case_id": "duplicate-decoded-escaped-key",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":1,\"v\\u0061lue\":2}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "native_profile_unavailable",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Underlying Foundation JSONDecoder lexical conversion/duplicates/parse precedence lacks independently pinned OS witness. Private port returns unavailable pending evidence; NOT assertion native rejects/accepts. Generic serde special RawValue behavior not native authority."
    },
    {
      "case_id": "unknown-exponent-integral",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":1e0}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "decimal": "1",
            "kind": "i64"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":1}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Composition witness: exact observed HealthMdJSONValue raw operand json-number-1e0 at unknown.value, whose branch explicitly decodes that same enum. Tagged enclosing raw frame not independently executed; synthetic trusted profile stimulus only, no whole native/iOS parity claim.",
      "native_operand_witness": {
        "encoded_utf8": "1",
        "id": "json-number-1e0",
        "profile": "json",
        "raw_input": "1e0",
        "result": "accepted",
        "value": {
          "decimal": "1",
          "kind": "i64"
        }
      }
    },
    {
      "case_id": "unknown-decimal-integral",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":1.0}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "decimal": "1",
            "kind": "i64"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":1}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Composition witness: exact observed HealthMdJSONValue raw operand json-number-1.0 at unknown.value, whose branch explicitly decodes that same enum. Tagged enclosing raw frame not independently executed; synthetic trusted profile stimulus only, no whole native/iOS parity claim.",
      "native_operand_witness": {
        "encoded_utf8": "1",
        "id": "json-number-1.0",
        "profile": "json",
        "raw_input": "1.0",
        "result": "accepted",
        "value": {
          "decimal": "1",
          "kind": "i64"
        }
      }
    },
    {
      "case_id": "unknown-minus-zero",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":-0}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "decimal": "0",
            "kind": "i64"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":0}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Composition witness: exact observed HealthMdJSONValue raw operand json-number--0 at unknown.value, whose branch explicitly decodes that same enum. Tagged enclosing raw frame not independently executed; synthetic trusted profile stimulus only, no whole native/iOS parity claim.",
      "native_operand_witness": {
        "encoded_utf8": "0",
        "id": "json-number--0",
        "profile": "json",
        "raw_input": "-0",
        "result": "accepted",
        "value": {
          "decimal": "0",
          "kind": "i64"
        }
      }
    },
    {
      "case_id": "unknown-u64-overflow-to-double",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":18446744073709551616}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "bits": "43f0000000000000",
            "kind": "f64"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":1.8446744073709552e+19}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Composition witness: exact observed HealthMdJSONValue raw operand json-number-18446744073709551616 at unknown.value, whose branch explicitly decodes that same enum. Tagged enclosing raw frame not independently executed; synthetic trusted profile stimulus only, no whole native/iOS parity claim.",
      "native_operand_witness": {
        "encoded_utf8": "1.8446744073709552e+19",
        "id": "json-number-18446744073709551616",
        "profile": "json",
        "raw_input": "18446744073709551616",
        "result": "accepted",
        "value": {
          "bits": "43f0000000000000",
          "kind": "f64"
        }
      }
    },
    {
      "case_id": "unknown-integer-underflow",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":-9223372036854775809}",
        "actions": []
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "bits": "c3e0000000000000",
            "kind": "f64"
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":-9.223372036854776e+18}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Composition witness: exact observed HealthMdJSONValue raw operand json-number--9223372036854775809 at unknown.value, whose branch explicitly decodes that same enum. Tagged enclosing raw frame not independently executed; synthetic trusted profile stimulus only, no whole native/iOS parity claim.",
      "native_operand_witness": {
        "encoded_utf8": "-9.223372036854776e+18",
        "id": "json-number--9223372036854775809",
        "profile": "json",
        "raw_input": "-9223372036854775809",
        "result": "accepted",
        "value": {
          "bits": "c3e0000000000000",
          "kind": "f64"
        }
      }
    },
    {
      "case_id": "quantity-underflow",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"quantity\",\"value\":1e-9999,\"unit\":\"x\"}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "native_profile_unavailable",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Underlying Foundation JSONDecoder lexical conversion/duplicates/parse precedence lacks independently pinned OS witness. Private port returns unavailable pending evidence; NOT assertion native rejects/accepts. Generic serde special RawValue behavior not native authority."
    },
    {
      "case_id": "ignored-extra-overflow",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"extra\":1e9999}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "native_profile_unavailable",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Underlying Foundation JSONDecoder lexical conversion/duplicates/parse precedence lacks independently pinned OS witness. Private port returns unavailable pending evidence; NOT assertion native rejects/accepts. Generic serde special RawValue behavior not native authority."
    },
    {
      "case_id": "unknown-special-serde-key",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":{\"$serde_json::private::RawValue\":\"1\"}}",
        "actions": []
      },
      "expected": {
        "kind": "private_failure",
        "failure": "native_profile_unavailable",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      },
      "source_basis": "Underlying Foundation JSONDecoder lexical conversion/duplicates/parse precedence lacks independently pinned OS witness. Private port returns unavailable pending evidence; NOT assertion native rejects/accepts. Generic serde special RawValue behavior not native authority."
    },
    {
      "case_id": "raw-byte-boundary",
      "group": "private_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      {\"type\":\"count\",\"value\":3}",
        "actions": [],
        "pre_call_recipe": {
          "kind": "prefix_spaces_then_count",
          "total_UTF8_bytes": 65536,
          "wire": "{\"type\":\"count\",\"value\":3}",
          "primitive_UTF8_bytes": 65536,
          "primitive_SHA256": "324959c1b27fa3fe12f54eff7271383ec19dcc4b729bde003578c6230fe1185c"
        }
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "boundary_accepted": true,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "canonical_UTF8_bytes": 26,
        "canonical_SHA256": "76bd5987102bff7a4721b1726798236cb3597a8245f1073c5001fb57064da7d9",
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "withValue_callbacks": 1,
        "current_phase_trace": [
          "before_decode",
          "before_decode",
          "after_profile",
          "after_profile",
          "before_read",
          "before_encode",
          "before_encode",
          "after_profile",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Private unmeasured batch budgets; recipe exact accounting frozen, not public history/profile restriction"
    },
    {
      "case_id": "string-byte-boundary",
      "group": "private_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"string\",\"value\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}",
        "actions": [],
        "pre_call_recipe": {
          "kind": "typed_string_ascii",
          "repeat": 8192,
          "primitive_UTF8_bytes": 8220,
          "primitive_SHA256": "eeac1799c30dcb30f84aa1712a772cdd51506a65777d8e69fb7b82ac7d72810b"
        }
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "boundary_accepted": true,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "view_recipe": {
          "kind": "typed_string_ascii",
          "repeat": 8192
        },
        "observed_reads": 1,
        "canonical_utf8": "{\"type\":\"string\",\"value\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}",
        "canonical_UTF8_bytes": 8220,
        "canonical_SHA256": "eeac1799c30dcb30f84aa1712a772cdd51506a65777d8e69fb7b82ac7d72810b",
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 1,
        "current_phase_trace": [
          "before_decode",
          "after_profile",
          "before_read",
          "before_encode",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Private unmeasured batch budgets; recipe exact accounting frozen, not public history/profile restriction"
    },
    {
      "case_id": "depth-boundary",
      "group": "private_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[null]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]}",
        "actions": [],
        "pre_call_recipe": {
          "kind": "unknown_array_nesting",
          "array_depth": 31,
          "leaf": null,
          "total_container_depth": 32,
          "primitive_UTF8_bytes": 98,
          "primitive_SHA256": "9ea5542386b80524356849a4dbdcd290e0cabbaf80b383cfeec87f146c32a4a6"
        }
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "boundary_accepted": true,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "view_recipe": {
          "kind": "unknown_array_nesting",
          "array_depth": 31,
          "leaf": null,
          "total_container_depth": 32
        },
        "observed_reads": 1,
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[null]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]}",
        "canonical_UTF8_bytes": 98,
        "canonical_SHA256": "9ea5542386b80524356849a4dbdcd290e0cabbaf80b383cfeec87f146c32a4a6",
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 1,
        "current_phase_trace": [
          "before_decode",
          "after_profile",
          "before_read",
          "before_encode",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Private unmeasured batch budgets; recipe exact accounting frozen, not public history/profile restriction"
    },
    {
      "case_id": "node-boundary",
      "group": "private_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":[null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]}",
        "actions": [],
        "pre_call_recipe": {
          "kind": "unknown_array_nulls",
          "total_nodes": 4096,
          "null_elements": 4093,
          "primitive_UTF8_bytes": 20498,
          "primitive_SHA256": "4057d60b1b7eeeeb9c8e11f2348986f29672116ae4fdf5882526bc1a00f779ad"
        }
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "boundary_accepted": true,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "view_recipe": {
          "kind": "unknown_array_nulls",
          "total_nodes": 4096,
          "null_elements": 4093
        },
        "observed_reads": 1,
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":[null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]}",
        "canonical_UTF8_bytes": 20498,
        "canonical_SHA256": "4057d60b1b7eeeeb9c8e11f2348986f29672116ae4fdf5882526bc1a00f779ad",
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 1,
        "current_phase_trace": [
          "before_decode",
          "after_profile",
          "before_read",
          "before_encode",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Private unmeasured batch budgets; recipe exact accounting frozen, not public history/profile restriction"
    },
    {
      "case_id": "foreign-value-own-view",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_controlled_read_only",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "read",
            "action": "foreign_factory_value_proxy"
          }
        ]
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "read_result": null,
        "current_read_calls": 0,
        "property_traps": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "foreign-request-own-value",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_controlled_read_only",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "read",
            "action": "foreign_callback_request_proxy_with_own_value"
          }
        ]
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "read_result": null,
        "current_read_calls": 0,
        "property_traps": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "revocation-between-same-lazy-reads",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "callback",
            "action": "execute_same_lazy_read_success_revoke_execute_again"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "not_authorized",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "first_read": "count3",
        "second_failure": "not_authorized",
        "read_current_calls": 2,
        "successful_materializations": 1,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "original-close-during-current",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "before_read_current",
            "action": "suspend_current_close_original_resume_success"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "owned_handoff_closed",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "successful_materializations": 0,
        "read_current_calls": 1,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "callback-return-expires-before-postcurrent",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_controlled_read_only",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "callback",
            "action": "save_read_return"
          },
          {
            "at": "after_callback_current",
            "action": "execute_saved_read"
          }
        ]
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "read_result": null,
        "current_read_calls": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "fresh-scope-reprovided-layer-no-revival",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_controlled_read_only",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "callback",
            "action": "save_read_return"
          },
          {
            "at": "after_callback",
            "action": "replace_current_method_provide_fresh_scope_execute_read"
          }
        ]
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "read_result": null,
        "replacement_current_calls": 0,
        "current_read_calls": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "original-close-before-first-profile",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "before_decode",
            "action": "close_original"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "owned_handoff_closed",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "profile_calls": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "source-purpose-detail-deny",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "before_decode_current",
            "action": "deny_current_source_or_purpose_or_detail_or_destination"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "not_authorized",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "profile_calls": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "close-inside-profile-then-fail",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "native_profile",
            "action": "close_original_then_fail_private"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "owned_handoff_closed",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "successful_materializations": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "reentrant-factory-busy",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "native_profile",
            "action": "decode_reenter_same_factory"
          }
        ]
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "reentry_failure": "private_value_busy",
        "outer_completion": true,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}"
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "native-profile-foreign-issuer",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "native_profile",
            "action": "return_foreign_factory_numeric_token"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "native_profile_unavailable",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "property_traps": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "native-profile-stale-same-wire",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "native_profile",
            "action": "return_prior_callback_token_same_primitive_wire"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "native_profile_unavailable",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "external-interruption-current-pending",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "before_read_current",
            "action": "suspend_signal_registered_then_external_interrupt"
          }
        ]
      },
      "expected": {
        "kind": "interruption",
        "failure": null,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_pending_cancel_ACK": true,
        "successful_materializations": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "close-then-defect-before-publication",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "before_publication_current",
            "action": "close_original_then_defect"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "owned_handoff_closed",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "canonical_published": false,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "escaped-callback-reuse-null",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_controlled_read_only",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "callback",
            "action": "save_view_then_return"
          },
          {
            "at": "after_callback",
            "action": "execute_saved_read_twice"
          }
        ]
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "read_results": [
          null,
          null
        ],
        "current_read_calls": 0,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "encode-rechecks-current",
      "group": "owned_lifetime",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3}",
        "actions": [
          {
            "at": "before_encode_current",
            "action": "revoke_after_successful_read"
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "not_authorized",
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "canonical_published": false,
        "successful_materializations": 1,
        "view": null,
        "canonical_utf8": null
      },
      "source_basis": "Independently authored captured originalScope/current/callback/membership contract; no candidate observation or expected selector passed to ports"
    },
    {
      "case_id": "nonfinite-bit-input",
      "group": "owned_numeric_input",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"duration\",\"seconds\":60}",
        "actions": [
          {
            "at": "native_profile_number",
            "action": "attempt_issue_nonfinite_bits_then_fail_non_finite_number",
            "bits": [
              "7ff0000000000000",
              "fff0000000000000",
              "7ff8000000000000"
            ]
          }
        ]
      },
      "expected": {
        "kind": "private_failure",
        "failure": "non_finite_number",
        "view": null,
        "canonical_utf8": null,
        "provider_echo": false,
        "allocations": 0,
        "release_ACKs": 0,
        "issuer_nonfinite_tokens": 0
      },
      "source_basis": "Source finite guard required; private native-profile callback receives actual raw60 slot and attempts invalid bit issuance, then returns fixed failure. Not a claim about Foundation parsing1e9999."
    },
    {
      "case_id": "observed-macos-count-integral-decimal",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":1.0}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row count-integral-decimal; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "count-integral-decimal",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "1",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":1}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-count-integral-exponent",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":1e0}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row count-integral-exponent; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "count-integral-exponent",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "1",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":1}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-count-fraction",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":1.5}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row count-fraction; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "count-fraction",
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_pipeline_observation": "native_rejected",
        "native_decoder_stage_error_not_inferred": true
      }
    },
    {
      "case_id": "observed-macos-count-extra",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"extra\":\"synthetic\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row count-extra; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "count-extra",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-quantity-negative-zero",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"quantity\",\"value\":-0,\"unit\":\"synthetic\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row quantity-negative-zero; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "quantity-negative-zero",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "quantity",
          "bits": "8000000000000000",
          "unit": "synthetic"
        },
        "canonical_utf8": "{\"type\":\"quantity\",\"unit\":\"synthetic\",\"value\":-0}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-quantity-integral-float",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"quantity\",\"value\":1.0,\"unit\":\"synthetic\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row quantity-integral-float; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "quantity-integral-float",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "quantity",
          "bits": "3ff0000000000000",
          "unit": "synthetic"
        },
        "canonical_utf8": "{\"type\":\"quantity\",\"unit\":\"synthetic\",\"value\":1}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-quantity-string-infinity",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"quantity\",\"value\":\"Infinity\",\"unit\":\"synthetic\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row quantity-string-infinity; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "quantity-string-infinity",
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_pipeline_observation": "native_rejected",
        "native_decoder_stage_error_not_inferred": true
      }
    },
    {
      "case_id": "observed-macos-unknown-array",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":[1.0,9223372036854775808,true,null]}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row unknown-array; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "unknown-array",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "array",
            "values": [
              {
                "decimal": "1",
                "kind": "i64"
              },
              {
                "decimal": "9223372036854775808",
                "kind": "u64"
              },
              {
                "kind": "boolean",
                "value": true
              },
              {
                "kind": "null"
              }
            ]
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":[1,9223372036854775808,true,null]}",
        "observed_reads": 1,
        "native_decode_calls": 2,
        "native_canonical_number_calls": 2,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-date-arbitrary-raw",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"date\",\"value\":\"synthetic\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row date-arbitrary-raw; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "date-arbitrary-raw",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "date",
          "value": "synthetic"
        },
        "canonical_utf8": "{\"type\":\"date\",\"value\":\"synthetic\"}",
        "observed_reads": 1,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-string-NUL",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"string\",\"value\":\"x\\u0000y\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row string-NUL; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "string-NUL",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "string",
          "value": "x\u0000y"
        },
        "canonical_utf8": "{\"type\":\"string\",\"value\":\"x\\u0000y\"}",
        "observed_reads": 1,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-category-missing-optional",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"category\",\"identifier\":\"synthetic\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row category-missing-optional; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "category-missing-optional",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "category",
          "identifier": "synthetic",
          "display": null,
          "raw_value": null
        },
        "canonical_utf8": "{\"identifier\":\"synthetic\",\"type\":\"category\"}",
        "observed_reads": 1,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-category-null-optional",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"category\",\"identifier\":\"synthetic\",\"display\":null,\"raw_value\":null}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row category-null-optional; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "category-null-optional",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "category",
          "identifier": "synthetic",
          "display": null,
          "raw_value": null
        },
        "canonical_utf8": "{\"identifier\":\"synthetic\",\"type\":\"category\"}",
        "observed_reads": 1,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-duplicate-type-count-first",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"type\":\"string\",\"value\":3}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row duplicate-type-count-first; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "duplicate-type-count-first",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-duplicate-type-string-first",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"string\",\"type\":\"count\",\"value\":\"x\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row duplicate-type-string-first; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "duplicate-type-string-first",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "string",
          "value": "x"
        },
        "canonical_utf8": "{\"type\":\"string\",\"value\":\"x\"}",
        "observed_reads": 1,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-duplicate-value",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":1,\"value\":2}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row duplicate-value; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "duplicate-value",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "1",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":1}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-duplicate-escaped-value",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":1,\"val\\u0075e\":2}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row duplicate-escaped-value; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "duplicate-escaped-value",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "1",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":1}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-unknown-Unicode-key-order",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":{\"z\":1,\"a\":2,\"A\":3,\"ä\":4,\"\\uE000\":5,\"😀\":6,\"10\":7,\"2\":8}}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row unknown-Unicode-key-order; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "unknown-Unicode-key-order",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "object",
            "entries": [
              [
                "10",
                {
                  "decimal": "7",
                  "kind": "i64"
                }
              ],
              [
                "2",
                {
                  "decimal": "8",
                  "kind": "i64"
                }
              ],
              [
                "A",
                {
                  "decimal": "3",
                  "kind": "i64"
                }
              ],
              [
                "a",
                {
                  "decimal": "2",
                  "kind": "i64"
                }
              ],
              [
                "z",
                {
                  "decimal": "1",
                  "kind": "i64"
                }
              ],
              [
                "ä",
                {
                  "decimal": "4",
                  "kind": "i64"
                }
              ],
              [
                "",
                {
                  "decimal": "5",
                  "kind": "i64"
                }
              ],
              [
                "😀",
                {
                  "decimal": "6",
                  "kind": "i64"
                }
              ]
            ]
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":{\"10\":7,\"2\":8,\"A\":3,\"a\":2,\"z\":1,\"ä\":4,\"\":5,\"😀\":6}}",
        "observed_reads": 1,
        "native_decode_calls": 8,
        "native_canonical_number_calls": 8,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-unknown-equivalent-keys",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":{\"a\":1,\"\\u0061\":2}}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row unknown-equivalent-keys; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "unknown-equivalent-keys",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "object",
            "entries": [
              [
                "a",
                {
                  "decimal": "1",
                  "kind": "i64"
                }
              ]
            ]
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":{\"a\":1}}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-unknown-nested-duplicate",
      "group": "source_value",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":{\"a\":{\"x\":1,\"x\":2}}}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row unknown-nested-duplicate; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "unknown-nested-duplicate",
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "unknown",
          "tag": "future_value",
          "value": {
            "kind": "object",
            "entries": [
              [
                "a",
                {
                  "kind": "object",
                  "entries": [
                    [
                      "x",
                      {
                        "decimal": "1",
                        "kind": "i64"
                      }
                    ]
                  ]
                }
              ]
            ]
          }
        },
        "canonical_utf8": "{\"type\":\"future_value\",\"value\":{\"a\":{\"x\":1}}}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false
      }
    },
    {
      "case_id": "observed-macos-timestamp-nine-unrepresentable",
      "group": "negative",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456789Z\"}",
        "actions": []
      },
      "source_basis": "Exact independently reviewed macOS source row timestamp-nine-unrepresentable; full raw input and observed canonical bytes; native pipeline rejection only when resultnative_rejected.",
      "native_source_golden_id": "timestamp-nine-unrepresentable",
      "expected": {
        "kind": "private_failure",
        "failure": "invalid_typed_value",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "native_pipeline_observation": "native_rejected",
        "native_decoder_stage_error_not_inferred": true
      }
    },
    {
      "case_id": "numeric-token-selected-1024",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000}",
        "actions": [],
        "raw_UTF8_bytes": 1056,
        "raw_SHA256": "fddeec4f2545e8753c481e4dc3df515012196403c21349e0af678ae0b2e75c78",
        "scanner_accounting": {
          "numeric_token_bytes": 1024
        },
        "profile_control": "No native semantic witness for selected1024-digit operand: captured profile reports fixed native_profile_unavailable"
      },
      "expected": {
        "kind": "private_failure",
        "failure": "native_profile_unavailable",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": [
          "before_decode",
          "before_decode"
        ]
      },
      "source_basis": "Global raw numeric token cap applied before selected source-profile callback. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "numeric-token-ignored-1024",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"ignored\":1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000}",
        "actions": [],
        "raw_UTF8_bytes": 1061,
        "raw_SHA256": "4c3b2e66655f99cc6751f821c36c10b38a2038ae6a0320cbe53dc1d38a4fc3bb",
        "scanner_accounting": {
          "numeric_token_bytes": 1024
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "withValue_callbacks": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": [
          "before_decode",
          "before_decode",
          "after_profile",
          "after_profile",
          "before_read",
          "before_encode",
          "before_encode",
          "after_profile",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Swift ignored CodingKeys remains ignored semantically, but global raw token cap includes skipped subtree. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "numeric-token-ignored-nested-1024",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"ignored\":{\"nested\":[1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000]}}",
        "actions": [],
        "raw_UTF8_bytes": 1074,
        "raw_SHA256": "0bca226cc22b60297097ed20c60d54c5bb420828a9096cb2c962b9d82a15ff9f",
        "scanner_accounting": {
          "numeric_token_bytes": 1024
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "withValue_callbacks": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": [
          "before_decode",
          "before_decode",
          "after_profile",
          "after_profile",
          "before_read",
          "before_encode",
          "before_encode",
          "after_profile",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Global counters never reset in ignored nested object/array. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "numeric-token-selected-1025",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"future_value\",\"value\":10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000}",
        "actions": [],
        "raw_UTF8_bytes": 1057,
        "raw_SHA256": "9dd32d91eb4b15bf94db7a1ef3a5438c918629d908dda4ba09a53e9e1b8d663f",
        "scanner_accounting": {
          "numeric_token_bytes": 1025
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": []
      },
      "source_basis": "Global raw numeric token cap applied before selected source-profile callback. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "numeric-token-ignored-1025",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"ignored\":10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000}",
        "actions": [],
        "raw_UTF8_bytes": 1062,
        "raw_SHA256": "a00ccc494c4539a26c6a301ba677f9c74cf0345fe489130a6eb50b3726cad9ea",
        "scanner_accounting": {
          "numeric_token_bytes": 1025
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": []
      },
      "source_basis": "Swift ignored CodingKeys remains ignored semantically, but global raw token cap includes skipped subtree. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "numeric-token-ignored-nested-1025",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"ignored\":{\"nested\":[10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000]}}",
        "actions": [],
        "raw_UTF8_bytes": 1075,
        "raw_SHA256": "16712ec324acb38e68f5b84a619df6da96e5a26c02548f51adaf687a8a27b2c8",
        "scanner_accounting": {
          "numeric_token_bytes": 1025
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": []
      },
      "source_basis": "Global counters never reset in ignored nested object/array. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "decoded-key-ascii-8192",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\":null}",
        "actions": [],
        "raw_UTF8_bytes": 8226,
        "raw_SHA256": "3967f312fd2d1e6faada2f113cd36053a7b40f18b99af83b1aabe951abf2d6cf",
        "scanner_accounting": {
          "decoded_key_UTF8_bytes": 8192,
          "raw_key_UTF8_bytes": 8192,
          "ignored_payload_materialized": false
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "withValue_callbacks": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": [
          "before_decode",
          "before_decode",
          "after_profile",
          "after_profile",
          "before_read",
          "before_encode",
          "before_encode",
          "after_profile",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Decoded EACH key UTF8 accounting before ignored CodingKeys materialization; escape spelling is not decoded byte count. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "decoded-key-ascii-8193",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\":null}",
        "actions": [],
        "raw_UTF8_bytes": 8227,
        "raw_SHA256": "13443ca9ed33361f5cd2d5a002eb67084dc986283b5c81e1a0f0f247a89338ae",
        "scanner_accounting": {
          "decoded_key_UTF8_bytes": 8193,
          "raw_key_UTF8_bytes": 8193,
          "ignored_payload_materialized": false
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": []
      },
      "source_basis": "Decoded EACH key UTF8 accounting before ignored CodingKeys materialization; escape spelling is not decoded byte count. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "decoded-key-escaped-8192",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\":null}",
        "actions": [],
        "raw_UTF8_bytes": 49186,
        "raw_SHA256": "63908ec5aa425f5479d8ab22b047787613c1efa236d5cf1be525ba61bb0efa36",
        "scanner_accounting": {
          "decoded_key_UTF8_bytes": 8192,
          "raw_key_UTF8_bytes": 49152,
          "ignored_payload_materialized": false
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "withValue_callbacks": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": [
          "before_decode",
          "before_decode",
          "after_profile",
          "after_profile",
          "before_read",
          "before_encode",
          "before_encode",
          "after_profile",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Decoded EACH key UTF8 accounting before ignored CodingKeys materialization; escape spelling is not decoded byte count. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "decoded-key-escaped-8193",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\\u0061\":null}",
        "actions": [],
        "raw_UTF8_bytes": 49192,
        "raw_SHA256": "13b60c420a0cce119f91c0505583337c7b93978c505171593a5ec94774d494c7",
        "scanner_accounting": {
          "decoded_key_UTF8_bytes": 8193,
          "raw_key_UTF8_bytes": 49158,
          "ignored_payload_materialized": false
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": []
      },
      "source_basis": "Decoded EACH key UTF8 accounting before ignored CodingKeys materialization; escape spelling is not decoded byte count. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "decoded-key-multibyte-8192",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"éééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé\":null}",
        "actions": [],
        "raw_UTF8_bytes": 8226,
        "raw_SHA256": "400996e04c6591b92d085aed442c23d36f9490316d4a83f881e3ea9098298531",
        "scanner_accounting": {
          "decoded_key_UTF8_bytes": 8192,
          "raw_key_UTF8_bytes": 8192,
          "ignored_payload_materialized": false
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "withValue_callbacks": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": [
          "before_decode",
          "before_decode",
          "after_profile",
          "after_profile",
          "before_read",
          "before_encode",
          "before_encode",
          "after_profile",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Decoded EACH key UTF8 accounting before ignored CodingKeys materialization; escape spelling is not decoded byte count. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "decoded-key-multibyte-8193",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"ééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééa\":null}",
        "actions": [],
        "raw_UTF8_bytes": 8227,
        "raw_SHA256": "5c646804b26c65e230356362d7685cb390226678e8a9d6951a73ff459235f8c5",
        "scanner_accounting": {
          "decoded_key_UTF8_bytes": 8193,
          "raw_key_UTF8_bytes": 8193,
          "ignored_payload_materialized": false
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": []
      },
      "source_basis": "Decoded EACH key UTF8 accounting before ignored CodingKeys materialization; escape spelling is not decoded byte count. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "decoded-key-ignored-nested-8192",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"ignored\":{\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\":null}}",
        "actions": [],
        "raw_UTF8_bytes": 8238,
        "raw_SHA256": "7dc2d7cf8e7d43334212f5f0bbbd14c1b9edd08d4a4c49a218c837b5c48e04f4",
        "scanner_accounting": {
          "decoded_key_UTF8_bytes": 8192,
          "raw_key_UTF8_bytes": 8192,
          "ignored_payload_materialized": false
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "completion",
        "failure": null,
        "view": {
          "type": "count",
          "decimal": "3",
          "unit": "count"
        },
        "canonical_utf8": "{\"type\":\"count\",\"value\":3}",
        "observed_reads": 1,
        "native_decode_calls": 1,
        "native_canonical_number_calls": 1,
        "withValue_callbacks": 1,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": [
          "before_decode",
          "before_decode",
          "after_profile",
          "after_profile",
          "before_read",
          "before_encode",
          "before_encode",
          "after_profile",
          "before_publication",
          "after_callback"
        ]
      },
      "source_basis": "Decoded EACH key UTF8 accounting before ignored CodingKeys materialization; escape spelling is not decoded byte count. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    },
    {
      "case_id": "decoded-key-ignored-nested-8193",
      "group": "private_scanner_boundary",
      "stimulus": {
        "operation": "decode_then_withValue_read_then_encode",
        "representation": "utf8",
        "payload": "{\"type\":\"count\",\"value\":3,\"ignored\":{\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\":null}}",
        "actions": [],
        "raw_UTF8_bytes": 8239,
        "raw_SHA256": "2ed723c94833fe1540fb45684407e0965b48e7d50183bca169f37bd0b2f30731",
        "scanner_accounting": {
          "decoded_key_UTF8_bytes": 8193,
          "raw_key_UTF8_bytes": 8193,
          "ignored_payload_materialized": false
        },
        "profile_control": "Ignored subtree never invokes profile; sole selected count3 uses original witnessed count fixture"
      },
      "expected": {
        "kind": "private_failure",
        "failure": "private_value_limit",
        "view": null,
        "canonical_utf8": null,
        "observed_reads": 0,
        "native_decode_calls": 0,
        "native_canonical_number_calls": 0,
        "withValue_callbacks": 0,
        "allocations": 0,
        "release_calls": 0,
        "release_ACKs": 0,
        "provider_echo": false,
        "current_phase_trace": []
      },
      "source_basis": "Decoded EACH key UTF8 accounting before ignored CodingKeys materialization; escape spelling is not decoded byte count. Private scanner accounting only; no Foundation classification of unobserved long token/key."
    }
  ],
  "missing_native_witnesses": [
    {
      "owner": "QUERY-NATIVE-CANONICAL-PROFILE",
      "trigger": "Before raw numeric/duplicates/native timestamp arbitrary Date/f64 parity",
      "needed": [
        "Foundation numeric/duplicate cases OUTSIDE exactly recorded46 rows and explicit source composition operands; no remaining claim that already observed1.0/1e0/-0/UInt64overflow still lacks its specific witness",
        "FiniteDouble native format/rounding throughoutbinary64 outside observed finite bit witnesses",
        "Ignored excluded nested numeric parse failure precedence and raw invalid Unicode outside source syntactic witnesses",
        "Arbitrary native Foundation Date across unobserved dates/epochs/SDK and full timestamp decode/reproduce behavior",
        "Canonical Unicode string/key normalization/ordering outside recorded Unicode map and exact known source strings"
      ]
    }
  ],
  "remaining_family_work": [
    {
      "id": "QUERY-OTHER-FAMILIES",
      "owner": "common query/evaluator coordinator",
      "trigger": "After this coverage family and exact typed foundation reviewed, before any other public query behavior admission",
      "requirements": "Separate next packets metric_series/chart, period comparison and explicit aggregation/count-overflow; raw source records/evidence; sleep sessions/fixed windows and overlap-safe authorized totals; workouts; workout-sleep alignment/nearest factual exclusions; derive_packet/training evidence/stable semantic packet IDs. All eight native operation tags and all nine O02 public query operations remain supported by current authorities, no mega evaluator task."
    },
    {
      "id": "QUERY-FULL-CONTEXT-PROJECTION",
      "owner": "common context and native-capture integration owner",
      "trigger": "Before claiming new candidate replaces HealthMdQueryContextProjector or encrypted context projector",
      "requirements": "Full catalog summary/archive/provider projection, canonical evidence locators/source digests, unknown archived metric preservation, enabled/unavailable precedence, provider-only no Apple placeholders, DST/IANA ownership/workout/sleep complete source fixtures; one shared business authority with separately qualified native capture."
    },
    {
      "id": "QUERY-NATIVE-CANONICAL-PROFILE",
      "owner": "exact query profile/serializer owner",
      "trigger": "Before request/response/cursor/packet native full byte parity or host digest/cursor use",
      "requirements": "Freeze whole Swift JSONEncoder sortedKeys/withoutEscapingSlashes, finiteDouble formatting and native Foundation Date epoch/arithmetic/reproduce-byte grammar. Generic serde canonical serializer is not Foundation query serializer. Unknown/raw numeric/duplicate-key decoding profile and exact dictionary ordering independently source proven; SHA/HMAC real primitives separate."
    },
    {
      "id": "QUERY-NATIVE-HOSTS-AND-CURSOR-CRYPTO",
      "owner": "Apple foreground/macOS encrypted context and Android native capability owners",
      "trigger": "Before any real snapshot/cursor/read admission or capability advertise",
      "requirements": "Protected cursor keys/authenticated logical dataset/source/current caller binding; actual per-page grants/source-purpose/detail/destination/external frontier, frozen foreground snapshot600s/background/terminal clears, stale no recapture, reconnect and SDK authorized source/current source callbacks. iPhone remains foregroundv3; Mac authorized encrypted snapshot; Android typed query currently unavailable with concrete next packet Health Connect query capture/fixtures/channel eligibility. No device build/data in planning."
    },
    {
      "id": "QUERY-PAGINATION-SURFACES-CONSUMERS",
      "owner": "core/CLI/MCP/UI common-operation integration coordinator",
      "trigger": "Before actual query profile public consumers or package exports/current cohort change",
      "requirements": "Canonical MCP14ordinaryCLI/21full13readonly exact catalogs independent of donor time.md40 obligations. Full response-byte/metadata bounds, source descriptors/missing intervals truncation,1MiB1000nativepage and2MiBminus16384/4096Rust aggregate accounting, opaque cursor nonadvance/cycle/replay, exact timeout/current grants/cancel/ACK, real physical oneEffect packed exports/source mappings. No mutable generated outputs/cohort widening here."
    },
    {
      "id": "QUERY-PERSONAL-DOMAINS-AND-HISTORY",
      "owner": "P02/K06 personal source-query and S06 acquisition coordinator",
      "trigger": "Before personal combined/location/usage queries or full donor history claims",
      "requirements": "All81 immutable personal grammar/identity/source precision/grant/deletion-revoke restoration fences; complete observed short sessions+retained history, native Date arithmetic distinct synthetic exactbasis; iOS aggregates do not fabricate exact sessions requiredS06. Health distance not GPS; aggregation/session/visit/inference and cross-device overlaps/source categories distinct. Browser URL/history/title and all input observation excluded before APIs/persistence; eligible separately granted nonbrowser titles allowed. No AGPL adoption or services/config/credential import."
    },
    {
      "id": "QUERY-SCHEDULE-DURABLE-CLOUD-RETIREMENT",
      "owner": "operation scheduling/cloud/durable/lifecycle rollout coordinator",
      "trigger": "Before durable delivery/cloud jobs/current public source promotion/reference retirement",
      "requirements": "Schedules/durable export/agent destinations, ambiguous delivery ledgers/ACK/crash/retry and latest independent suppression outside backups, tenant/source/purpose/grants/recipient-copy limits; cloud policy remains open. Actual UI/CLI/native/signed/external clients/full8/4/5 profile consumers and full no-Rust packaging/rollback recovery proofs before reference retirement; no family closure."
    }
  ],
  "qualification": {
    "implementation": false,
    "tests": false,
    "native_parity": false,
    "source_grants": false,
    "public_profile": false,
    "consumer_admission": false,
    "raw_unavailable_cases_not_native_rejection": true
  },
  "source_input_port_rule": "Pure profile witnesses keyed only actual raw token/context/bits/canonical value, never fixturecaseid or expected output; before test driver, independently freeze exact full source input corpus. Profile scalar ports do not authenticate grants or replace tagged codec. Duplicate unresolved requests remain unavailable until reviewed primarysource witness; preserve raw originals. Full46 native input rows retained unchanged; fake scalar stimulus may select only raw token/context/bits/profile binding, never native row id/case id/expected response. Exact native rows are authentic source observations executed by ROOT; author executes nothing.",
  "native_source_witness": {
    "host_profile": "Observed macOS26.5.1/build25F80; Swift6.3.3; SDK26.5; targetarm64-apple-macosx26.0 only. Other OS/SDK/native apps remain unqualified.",
    "execution_owner": "ROOT",
    "independent_reviewer": "effect_baseline_review",
    "independent_review": {
      "path": "/private/tmp/healthmd-native-query-source-witness-effect-baseline-review.json",
      "sha256": "ab2a8220f0bbced1d8ea27da90e81d31988f5bf322da5d6e06d9ab16f1b5a034",
      "bytes": 4668
    },
    "manifest": {
      "path": "/private/tmp/healthmd-native-query-source-witness/pre-execution-manifest.json",
      "sha256": "e411167f6dd945cd5215509fcba021bf04281da39f28061ab373fdcd93e2dcf0",
      "bytes": 3591,
      "value": {
        "scope": "Native copied source semantics only, not candidate expected values, public/native app or collector qualification.",
        "source_revision": "32f38da439c0489648e99933c99d88805b76ca7b",
        "native_sources": [
          {
            "path": "apps/apple/HealthMd/Shared/Query/QueryTypedValue.swift",
            "sha256": "1658be7cf1db8ad530356eebf2e986a501ef223f57ffc2571a9540817e57916f",
            "bytes": 8432
          },
          {
            "path": "apps/apple/HealthMd/Shared/Query/QueryCanonicalSerializer.swift",
            "sha256": "b6b2de86e7cfd0c03c7105ae65750b23189ab7f163e4823ee4d983bcc0445feb",
            "bytes": 6998
          },
          {
            "path": "apps/apple/HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift",
            "sha256": "8a69809edf797dae23af3b7e30af3e50c51e43a2de53febcadf4646a6931e2f7",
            "bytes": 42303
          }
        ],
        "scratch_files": [
          {
            "path": "/private/tmp/healthmd-native-query-source-witness/NativeSources.swift",
            "sha256": "b3f268a457d28cb226a355ab3220ce522abc9f890e72997d6811a2ec1a07baf1",
            "bytes": 12532
          },
          {
            "path": "/private/tmp/healthmd-native-query-source-witness/main.swift",
            "sha256": "e58e139eddedb9a84354bff20fc43416bb37187f9c1218819658c1c607ab1687",
            "bytes": 3778
          },
          {
            "path": "/private/tmp/healthmd-native-query-source-witness/input-rows.json",
            "sha256": "9d4075b0e5f3f7aff2e5a54a2d3acf9ca6fc8e4f66ae39e93126f1c7e97d8ed9",
            "bytes": 5488
          }
        ],
        "source_selection": "Full QueryTypedValue.swift; exact original data/string/decode methods and encoder/decoder factories from QueryCanonicalSerializer, wrapped same enum name; entire CanonicalRFC3339UTC enum raw text. No source semantic modifications.",
        "rows": 46,
        "Date_inputs": 6,
        "qualified_host": "Observed macOS26.5.1/build25F80; Swift6.3.3; SDK26.5; targetarm64-apple-macosx26.0 only. Other OS/SDK/native apps remain unqualified.",
        "compiler": {
          "invoked_path": "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
          "physical": {
            "path": "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend",
            "sha256": "2ed38571e92c0283091838c1649e27650ad9c99950288e883c7b2dc6c4ce89fb",
            "bytes": 171036592
          }
        },
        "SDK": {
          "path": "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk",
          "realpath": "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
          "settings": {
            "path": "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk/SDKSettings.json",
            "sha256": "f8d005f09381389167f9e0aeaa169bc9e7dff162ef22ca2fd8e98df7ff1acafe",
            "bytes": 7774
          }
        },
        "argv_compile": [
          "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
          "-swift-version",
          "6",
          "-target",
          "arm64-apple-macosx26.0",
          "-sdk",
          "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk",
          "-module-cache-path",
          "/private/tmp/healthmd-native-query-source-witness/module-cache",
          "/private/tmp/healthmd-native-query-source-witness/NativeSources.swift",
          "/private/tmp/healthmd-native-query-source-witness/main.swift",
          "-o",
          "/private/tmp/healthmd-native-query-source-witness/native-witness"
        ],
        "argv_run": [
          "/private/tmp/healthmd-native-query-source-witness/native-witness",
          "/private/tmp/healthmd-native-query-source-witness/input-rows.json"
        ]
      }
    },
    "execution": {
      "path": "/private/tmp/healthmd-native-query-source-witness/execution-report.json",
      "sha256": "17c71d7b67f902369656fa42d742228ad4a488b245cca0d667bb3744744dc92e",
      "bytes": 4054,
      "value": {
        "result": "passed",
        "scope": "Native copied source semantics only, not candidate expected values, public/native app or collector qualification.",
        "qualification": false,
        "host": "Observed macOS26.5.1/build25F80; Swift6.3.3; SDK26.5; targetarm64-apple-macosx26.0 only. Other OS/SDK/native apps remain unqualified.",
        "manifest_sha256": "e411167f6dd945cd5215509fcba021bf04281da39f28061ab373fdcd93e2dcf0",
        "harness_sha256": "d18f4181fd9878ae14db8e949ab45f84d89073c9b3a676d66e0e778ac8deb43b",
        "binary": {
          "bytes": 221344,
          "sha256": "a9ff0e7571117f467fcf0c2a917451a9a99f8bad599794fa8a843a6960a57f22"
        },
        "compile": {
          "result": "passed",
          "code": 0,
          "signal": null,
          "reason": null,
          "observed_output_bytes": 0,
          "retained_output_bytes": 0,
          "retained_raw_bytes": 0,
          "retained_raw_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "observed_raw_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "escalation": false,
          "parent_reaped": true,
          "group_absent": true,
          "cleanup_ack": true,
          "cleanup_deadline_missed": false,
          "late_physical_cleanup_observed": false,
          "group_observation": "absent_esrch",
          "supervisor_os_faults": {
            "group_query_denied": 0,
            "group_query_unverified": 0,
            "group_signal_denied": 0,
            "group_signal_unverified": 0
          }
        },
        "execution": {
          "result": "passed",
          "code": 0,
          "signal": null,
          "reason": null,
          "observed_output_bytes": 11656,
          "retained_output_bytes": 11656,
          "retained_raw_bytes": 11656,
          "retained_raw_sha256": "af7aab0daeaf88bd381900fb915dc1a9c11d28ee1480aaef169ea91a669b960e",
          "observed_raw_sha256": "af7aab0daeaf88bd381900fb915dc1a9c11d28ee1480aaef169ea91a669b960e",
          "escalation": false,
          "parent_reaped": true,
          "group_absent": true,
          "cleanup_ack": true,
          "cleanup_deadline_missed": false,
          "late_physical_cleanup_observed": false,
          "group_observation": "absent_esrch",
          "supervisor_os_faults": {
            "group_query_denied": 0,
            "group_query_unverified": 0,
            "group_signal_denied": 0,
            "group_signal_unverified": 0
          }
        },
        "argv_compile": [
          "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
          "-swift-version",
          "6",
          "-target",
          "arm64-apple-macosx26.0",
          "-sdk",
          "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk",
          "-module-cache-path",
          "/private/tmp/healthmd-native-query-source-witness/module-cache",
          "/private/tmp/healthmd-native-query-source-witness/NativeSources.swift",
          "/private/tmp/healthmd-native-query-source-witness/main.swift",
          "-o",
          "/private/tmp/healthmd-native-query-source-witness/native-witness"
        ],
        "argv_run": [
          "/private/tmp/healthmd-native-query-source-witness/native-witness",
          "/private/tmp/healthmd-native-query-source-witness/input-rows.json"
        ],
        "cwd": "/private/tmp/healthmd-native-query-source-witness",
        "env": {
          "PATH": "/usr/bin:/bin",
          "HOME": "/Users/codybontecou",
          "TMPDIR": "/private/tmp/healthmd-native-query-source-witness/tmp",
          "LANG": "C",
          "LC_ALL": "C",
          "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"
        },
        "wall_ms": 2232,
        "source_after_matches": true,
        "rows": 46,
        "Date_inputs": 6,
        "shape_matches": true,
        "native_output": {
          "path": "/private/tmp/healthmd-native-query-source-witness/native-output.json",
          "bytes": 11656,
          "sha256": "af7aab0daeaf88bd381900fb915dc1a9c11d28ee1480aaef169ea91a669b960e"
        },
        "limits": [
          "Current macOS Foundation native copied source observations only. Not iOS/otherSwiftSDK/fullapp/nativecollector/client/deployed qualification.",
          "No TypeScript candidate used to generate expectations. Exact frozen native source selected before compilation; synthetic inputs only.",
          "Source/compiler/SDK metadata pins bound; no claim complete dyld library or whole SDK graph qualified."
        ]
      }
    },
    "output": {
      "path": "/private/tmp/healthmd-native-query-source-witness/native-output.json",
      "sha256": "af7aab0daeaf88bd381900fb915dc1a9c11d28ee1480aaef169ea91a669b960e",
      "bytes": 11656,
      "value": {
        "dates": [
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
        "native_date_subtraction": {
          "end_reference_bits": "c1cd27e43f733333",
          "end_unix_bits": "3ff19999a0000000",
          "exposed_unix_subtraction_bits": "3ff0000000000000",
          "input_end_bits": "3ff199999999999a",
          "input_start_bits": "3fb999999999999a",
          "start_reference_bits": "c1cd27e43ff33333",
          "start_unix_bits": "3fb9999a00000000",
          "timeIntervalSince_bits": "3ff0000000000000"
        },
        "rows": [
          {
            "encoded_utf8": "0",
            "id": "json-number-0",
            "profile": "json",
            "raw_input": "0",
            "result": "accepted",
            "value": {
              "decimal": "0",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "0",
            "id": "json-number--0",
            "profile": "json",
            "raw_input": "-0",
            "result": "accepted",
            "value": {
              "decimal": "0",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "1",
            "id": "json-number-1",
            "profile": "json",
            "raw_input": "1",
            "result": "accepted",
            "value": {
              "decimal": "1",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "1",
            "id": "json-number-1.0",
            "profile": "json",
            "raw_input": "1.0",
            "result": "accepted",
            "value": {
              "decimal": "1",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "1",
            "id": "json-number-1e0",
            "profile": "json",
            "raw_input": "1e0",
            "result": "accepted",
            "value": {
              "decimal": "1",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "1.5",
            "id": "json-number-1.5",
            "profile": "json",
            "raw_input": "1.5",
            "result": "accepted",
            "value": {
              "bits": "3ff8000000000000",
              "kind": "f64"
            }
          },
          {
            "encoded_utf8": "9007199254740993",
            "id": "json-number-9007199254740993",
            "profile": "json",
            "raw_input": "9007199254740993",
            "result": "accepted",
            "value": {
              "decimal": "9007199254740993",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "9223372036854775807",
            "id": "json-number-9223372036854775807",
            "profile": "json",
            "raw_input": "9223372036854775807",
            "result": "accepted",
            "value": {
              "decimal": "9223372036854775807",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "9223372036854775808",
            "id": "json-number-9223372036854775808",
            "profile": "json",
            "raw_input": "9223372036854775808",
            "result": "accepted",
            "value": {
              "decimal": "9223372036854775808",
              "kind": "u64"
            }
          },
          {
            "encoded_utf8": "18446744073709551615",
            "id": "json-number-18446744073709551615",
            "profile": "json",
            "raw_input": "18446744073709551615",
            "result": "accepted",
            "value": {
              "decimal": "18446744073709551615",
              "kind": "u64"
            }
          },
          {
            "encoded_utf8": "1.8446744073709552e+19",
            "id": "json-number-18446744073709551616",
            "profile": "json",
            "raw_input": "18446744073709551616",
            "result": "accepted",
            "value": {
              "bits": "43f0000000000000",
              "kind": "f64"
            }
          },
          {
            "encoded_utf8": "-9.223372036854776e+18",
            "id": "json-number--9223372036854775809",
            "profile": "json",
            "raw_input": "-9223372036854775809",
            "result": "accepted",
            "value": {
              "bits": "c3e0000000000000",
              "kind": "f64"
            }
          },
          {
            "encoded_utf8": "1e+308",
            "id": "json-number-1e308",
            "profile": "json",
            "raw_input": "1e308",
            "result": "accepted",
            "value": {
              "bits": "7fe1ccf385ebc8a0",
              "kind": "f64"
            }
          },
          {
            "id": "json-number-1e309",
            "profile": "json",
            "raw_input": "1e309",
            "result": "native_rejected"
          },
          {
            "encoded_utf8": "0",
            "id": "json-number-1e-400",
            "profile": "json",
            "raw_input": "1e-400",
            "result": "accepted",
            "value": {
              "decimal": "0",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "0",
            "id": "json-number--1e-400",
            "profile": "json",
            "raw_input": "-1e-400",
            "result": "accepted",
            "value": {
              "decimal": "0",
              "kind": "i64"
            }
          },
          {
            "encoded_utf8": "5e-324",
            "id": "json-number-5e-324",
            "profile": "json",
            "raw_input": "5e-324",
            "result": "accepted",
            "value": {
              "bits": "0000000000000001",
              "kind": "f64"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"count\",\"value\":9007199254740993}",
            "id": "count-exact",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":9007199254740993}",
            "result": "accepted",
            "value": {
              "decimal": "9007199254740993",
              "kind": "count"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"count\",\"value\":9223372036854775807}",
            "id": "count-max",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":9223372036854775807}",
            "result": "accepted",
            "value": {
              "decimal": "9223372036854775807",
              "kind": "count"
            }
          },
          {
            "id": "count-overflow",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":9223372036854775808}",
            "result": "native_rejected"
          },
          {
            "encoded_utf8": "{\"type\":\"count\",\"value\":1}",
            "id": "count-integral-decimal",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":1.0}",
            "result": "accepted",
            "value": {
              "decimal": "1",
              "kind": "count"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"count\",\"value\":1}",
            "id": "count-integral-exponent",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":1e0}",
            "result": "accepted",
            "value": {
              "decimal": "1",
              "kind": "count"
            }
          },
          {
            "id": "count-fraction",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":1.5}",
            "result": "native_rejected"
          },
          {
            "encoded_utf8": "{\"type\":\"count\",\"value\":3}",
            "id": "count-extra",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":3,\"extra\":\"synthetic\"}",
            "result": "accepted",
            "value": {
              "decimal": "3",
              "kind": "count"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"quantity\",\"unit\":\"synthetic\",\"value\":-0}",
            "id": "quantity-negative-zero",
            "profile": "typed",
            "raw_input": "{\"type\":\"quantity\",\"value\":-0,\"unit\":\"synthetic\"}",
            "result": "accepted",
            "value": {
              "bits": "8000000000000000",
              "kind": "quantity",
              "unit": "synthetic"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"quantity\",\"unit\":\"synthetic\",\"value\":1}",
            "id": "quantity-integral-float",
            "profile": "typed",
            "raw_input": "{\"type\":\"quantity\",\"value\":1.0,\"unit\":\"synthetic\"}",
            "result": "accepted",
            "value": {
              "bits": "3ff0000000000000",
              "kind": "quantity",
              "unit": "synthetic"
            }
          },
          {
            "id": "quantity-string-infinity",
            "profile": "typed",
            "raw_input": "{\"type\":\"quantity\",\"value\":\"Infinity\",\"unit\":\"synthetic\"}",
            "result": "native_rejected"
          },
          {
            "encoded_utf8": "{\"type\":\"future_value\"}",
            "id": "unknown-absent",
            "profile": "typed",
            "raw_input": "{\"type\":\"future_value\"}",
            "result": "accepted",
            "value": {
              "kind": "unknown",
              "tag": "future_value",
              "value": null
            }
          },
          {
            "encoded_utf8": "{\"type\":\"future_value\"}",
            "id": "unknown-null",
            "profile": "typed",
            "raw_input": "{\"type\":\"future_value\",\"value\":null}",
            "result": "accepted",
            "value": {
              "kind": "unknown",
              "tag": "future_value",
              "value": null
            }
          },
          {
            "encoded_utf8": "{\"type\":\"future_value\",\"value\":[1,9223372036854775808,true,null]}",
            "id": "unknown-array",
            "profile": "typed",
            "raw_input": "{\"type\":\"future_value\",\"value\":[1.0,9223372036854775808,true,null]}",
            "result": "accepted",
            "value": {
              "kind": "unknown",
              "tag": "future_value",
              "value": {
                "items": [
                  {
                    "decimal": "1",
                    "kind": "i64"
                  },
                  {
                    "decimal": "9223372036854775808",
                    "kind": "u64"
                  },
                  {
                    "kind": "boolean",
                    "value": true
                  },
                  {
                    "kind": "null"
                  }
                ],
                "kind": "array"
              }
            }
          },
          {
            "encoded_utf8": "{\"type\":\"date\",\"value\":\"2026-02-30\"}",
            "id": "date-invalid-calendar-raw",
            "profile": "typed",
            "raw_input": "{\"type\":\"date\",\"value\":\"2026-02-30\"}",
            "result": "accepted",
            "value": {
              "kind": "date",
              "value": "2026-02-30"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"date\",\"value\":\"synthetic\"}",
            "id": "date-arbitrary-raw",
            "profile": "typed",
            "raw_input": "{\"type\":\"date\",\"value\":\"synthetic\"}",
            "result": "accepted",
            "value": {
              "kind": "date",
              "value": "synthetic"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"string\",\"value\":\"x\\u0000y\"}",
            "id": "string-NUL",
            "profile": "typed",
            "raw_input": "{\"type\":\"string\",\"value\":\"x\\u0000y\"}",
            "result": "accepted",
            "value": {
              "kind": "string",
              "value": "x\u0000y"
            }
          },
          {
            "encoded_utf8": "{\"identifier\":\"synthetic\",\"type\":\"category\"}",
            "id": "category-missing-optional",
            "profile": "typed",
            "raw_input": "{\"type\":\"category\",\"identifier\":\"synthetic\"}",
            "result": "accepted",
            "value": {
              "display": null,
              "identifier": "synthetic",
              "kind": "category",
              "raw_value": null
            }
          },
          {
            "encoded_utf8": "{\"identifier\":\"synthetic\",\"type\":\"category\"}",
            "id": "category-null-optional",
            "profile": "typed",
            "raw_input": "{\"type\":\"category\",\"identifier\":\"synthetic\",\"display\":null,\"raw_value\":null}",
            "result": "accepted",
            "value": {
              "display": null,
              "identifier": "synthetic",
              "kind": "category",
              "raw_value": null
            }
          },
          {
            "encoded_utf8": "{\"type\":\"count\",\"value\":3}",
            "id": "duplicate-type-count-first",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"type\":\"string\",\"value\":3}",
            "result": "accepted",
            "value": {
              "decimal": "3",
              "kind": "count"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"string\",\"value\":\"x\"}",
            "id": "duplicate-type-string-first",
            "profile": "typed",
            "raw_input": "{\"type\":\"string\",\"type\":\"count\",\"value\":\"x\"}",
            "result": "accepted",
            "value": {
              "kind": "string",
              "value": "x"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"count\",\"value\":1}",
            "id": "duplicate-value",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":1,\"value\":2}",
            "result": "accepted",
            "value": {
              "decimal": "1",
              "kind": "count"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"count\",\"value\":1}",
            "id": "duplicate-escaped-value",
            "profile": "typed",
            "raw_input": "{\"type\":\"count\",\"value\":1,\"val\\u0075e\":2}",
            "result": "accepted",
            "value": {
              "decimal": "1",
              "kind": "count"
            }
          },
          {
            "encoded_utf8": "{\"type\":\"future_value\",\"value\":{\"10\":7,\"2\":8,\"A\":3,\"a\":2,\"z\":1,\"ä\":4,\"\":5,\"😀\":6}}",
            "id": "unknown-Unicode-key-order",
            "profile": "typed",
            "raw_input": "{\"type\":\"future_value\",\"value\":{\"z\":1,\"a\":2,\"A\":3,\"ä\":4,\"\\uE000\":5,\"😀\":6,\"10\":7,\"2\":8}}",
            "result": "accepted",
            "value": {
              "kind": "unknown",
              "tag": "future_value",
              "value": {
                "fields": {
                  "😀": {
                    "decimal": "6",
                    "kind": "i64"
                  },
                  "2": {
                    "decimal": "8",
                    "kind": "i64"
                  },
                  "10": {
                    "decimal": "7",
                    "kind": "i64"
                  },
                  "a": {
                    "decimal": "2",
                    "kind": "i64"
                  },
                  "A": {
                    "decimal": "3",
                    "kind": "i64"
                  },
                  "ä": {
                    "decimal": "4",
                    "kind": "i64"
                  },
                  "z": {
                    "decimal": "1",
                    "kind": "i64"
                  },
                  "": {
                    "decimal": "5",
                    "kind": "i64"
                  }
                },
                "kind": "object"
              }
            }
          },
          {
            "encoded_utf8": "{\"type\":\"future_value\",\"value\":{\"a\":1}}",
            "id": "unknown-equivalent-keys",
            "profile": "typed",
            "raw_input": "{\"type\":\"future_value\",\"value\":{\"a\":1,\"\\u0061\":2}}",
            "result": "accepted",
            "value": {
              "kind": "unknown",
              "tag": "future_value",
              "value": {
                "fields": {
                  "a": {
                    "decimal": "1",
                    "kind": "i64"
                  }
                },
                "kind": "object"
              }
            }
          },
          {
            "encoded_utf8": "{\"type\":\"future_value\",\"value\":{\"a\":{\"x\":1}}}",
            "id": "unknown-nested-duplicate",
            "profile": "typed",
            "raw_input": "{\"type\":\"future_value\",\"value\":{\"a\":{\"x\":1,\"x\":2}}}",
            "result": "accepted",
            "value": {
              "kind": "unknown",
              "tag": "future_value",
              "value": {
                "fields": {
                  "a": {
                    "fields": {
                      "x": {
                        "decimal": "1",
                        "kind": "i64"
                      }
                    },
                    "kind": "object"
                  }
                },
                "kind": "object"
              }
            }
          },
          {
            "encoded_utf8": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456717Z\"}",
            "id": "timestamp-nine-representable",
            "profile": "typed",
            "raw_input": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456717Z\"}",
            "result": "accepted",
            "value": {
              "kind": "timestamp",
              "reference_bits": "41c58214400fcd6e",
              "unix_bits": "41d954fc4007e6b7"
            }
          },
          {
            "id": "timestamp-nine-unrepresentable",
            "profile": "typed",
            "raw_input": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456789Z\"}",
            "result": "native_rejected"
          },
          {
            "id": "timestamp-short",
            "profile": "typed",
            "raw_input": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123Z\"}",
            "result": "native_rejected"
          },
          {
            "id": "timestamp-carry",
            "profile": "typed",
            "raw_input": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.999999999Z\"}",
            "result": "native_rejected"
          }
        ],
        "scope": "current_macOS_Foundation_native_source_witness_only"
      }
    },
    "policy": "Exact46 raw observed rows +6 native Date construction observations retained. Each observed decoded tag/bits/decimal/canonical text is limited macOS26.5.1/Swift6.3.3/SDK26.5 source golden, not extrapolation to iOS, arbitrary lexemes/fullNative JSON/Date/Unicode grammar. Native_rejected is entire decode+encode pipeline rejection; private fixed error chosen separately, no raw native exception asserted."
  },
  "native_golden_case_mapping": {
    "count-exact": "count-beyond-binary64",
    "count-max": "count-i64-max",
    "count-overflow": "count-overflow-positive",
    "count-integral-decimal": "observed-macos-count-integral-decimal",
    "count-integral-exponent": "observed-macos-count-integral-exponent",
    "count-fraction": "observed-macos-count-fraction",
    "count-extra": "observed-macos-count-extra",
    "quantity-negative-zero": "observed-macos-quantity-negative-zero",
    "quantity-integral-float": "observed-macos-quantity-integral-float",
    "quantity-string-infinity": "observed-macos-quantity-string-infinity",
    "unknown-absent": "unknown-value-absent",
    "unknown-null": "unknown-value-null",
    "unknown-array": "observed-macos-unknown-array",
    "date-invalid-calendar-raw": "date-not-calendar-validator",
    "date-arbitrary-raw": "observed-macos-date-arbitrary-raw",
    "string-NUL": "observed-macos-string-NUL",
    "category-missing-optional": "observed-macos-category-missing-optional",
    "category-null-optional": "observed-macos-category-null-optional",
    "duplicate-type-count-first": "observed-macos-duplicate-type-count-first",
    "duplicate-type-string-first": "observed-macos-duplicate-type-string-first",
    "duplicate-value": "observed-macos-duplicate-value",
    "duplicate-escaped-value": "observed-macos-duplicate-escaped-value",
    "unknown-Unicode-key-order": "observed-macos-unknown-Unicode-key-order",
    "unknown-equivalent-keys": "observed-macos-unknown-equivalent-keys",
    "unknown-nested-duplicate": "observed-macos-unknown-nested-duplicate",
    "timestamp-nine-representable": "timestamp-native-rounded-construction-witness",
    "timestamp-nine-unrepresentable": "observed-macos-timestamp-nine-unrepresentable",
    "timestamp-short": "timestamp-native-reject-1",
    "timestamp-carry": "timestamp-native-reject-5"
  },
  "native_profile_contract_amendment": {
    "duplicates": "All exactly observed duplicate rows firstwins, including escaped-equivalent/nested unknown; no generic serde lastwins. Unobserved duplicate situations require profile evidence before promotion.",
    "number_operand_witnesses": "Source profile numeric context must distinguish direct Double quantity from HealthMdJSONValue integer-first: raw-0 quantity f64negativezero vs JSON i640. Integral1.0/1e0 count i641 exactly observed; underflow±1e-400 JSON i640 only, never extrapolate1e-9999 quantity.",
    "canonical": "ObservedDouble1 encodes1,negativezero encodes-0, UInt64overflow encodes1.8446744073709552e+19; acceptedserde renderer1.0/-0.0 is not substitution. Use native pure profile capability; existing integer helpers only exact proven intersection.",
    "dates": "Timestamp view may retain nullable Foundation reference and exposed Unix binary64 fields when independently observed; never reinterpret input_constructorbits as exposed Unix bits or Personal native_source_arithmetic. Civil date String no calendar validation.",
    "string": "NUL validString fromexact native row; ignoredCodingKeys retained lenient. Unicode-key bytes exact witness only; no normalization/globalsort equivalence claim."
  },
  "observation_contract": {
    "envelope": [
      "kind",
      "failure",
      "view or view_recipe",
      "canonical_utf8 or canonical_recipe",
      "allocations",
      "release_calls",
      "release_ACKs",
      "provider_echo"
    ],
    "native_decode_calls": "Count each actual NativeProfile.number/timestamp invocation. canonicalNumber calls counted independently; all Current invocation phase trace derived from actual calls, never case ID/expected fields.",
    "current_protocol": "decode enters before_decode once; each native Effect callback execution is preceded by before_decode and followed by after_profile; after construction decode performs after_profile once. Every own active read enters before_read once; each encode enters before_encode then each synchronous canonicalNumber callback has originalScope/membership/context recheck and current before_encode/after_profile around callback; before_publication after complete text. Actual withValue callback inner ensuring expires before after_callback current. Foreign/expired read returns null with zero current.",
    "profile_state": "Finite token issuer bound exact frame, slot, callback, factory and originalScope; unavailable native witnesses return fixed safe unavailable, no grant creation. Profile callback returns fixed Code, no raw errors.",
    "recipes": "Closed positive/private boundary recipe expansion counts root typed object and type string as nodes; unknown payload array contributes one node and each null one node. Root object counts depth1. Depth32 boundary uses31 nested payload arrays, depth33 rejection uses32. No public history cap.",
    "lifetime_controls": "Actual controller Deferred readiness and known startImmediately child bodies before external interrupt/close; no sleeps/scheduler yield assumptions. The factory owns only graph tokens, so all resource allocation/release/ACK zero; callback cancellation acknowledged as its own distinct fake control observation, not physical resource ACK.",
    "pre_call_expansion": "Recipe controls belong only to inert fixture driver; expand to the frozen primitive utf8 payload BEFORE decode. No recipe object enters candidate. Four boundary scenes call decode then withValue/read then encode in the SAME actual callback, with exact canonical bytes/hash and actual Current/profile/callback trace."
  },
  "stage1_amendment_history": {
    "initial_draft_vector_sha256": "566702774635cedf2ac5dfd9b275effc6792581a9415fbad7a3be9e1d39313f1",
    "pre_native_witness_vector_sha256": "c85d16b412ff3486046dd88d25f9394b21eaed263903dc7940375eca98565a6b",
    "native_witness_intermediate_vector_sha256": "431503c5765389962a371f42c7649e631895bf819a76a803327b0634f8af6709",
    "closure_amendment": "Before independent handoff, fix closed observations completion/null versus failure, recipe exact global node/depth totals, and remove guessed static Current trace in favor of exact callback protocol; no candidate execution."
  },
  "timestamp_issue_contract": {
    "typed_operand": "NativeTimestampInput",
    "boundary": "Membership and active slot/callback/frame/factory/originalScope before inspecting issuer operands. canonical/reference_bits/unix_bits are separate primitive unknown arguments, rejected using typeof/lexical bounds only; no object properties/getters/Proxy/coercion. NativeTimestampInput names the source-input record grammar, not an untrusted runtime object transport.",
    "canonical": "Exactly bounded30-character ASCII YYYY-MM-DDTHH:mm:ss.nnnnnnnnnZ already supplied by captured trusted timestamp profile; no Date reconstruction or Unix arithmetic. Source profile validates/reproduces native Date.",
    "bits": "Each optional operand exactly16 lowercase hexadecimal ASCII digits and finite IEEE754 binary64 (exponent field not all ones). Each supplied field retained separately; absent stays absent. No inferred relation or recovery from canonical text.",
    "binding": "Issued token records exact canonical and independently supplied operand primitives with same callback/frame/slot/factory ownership. All source-input records below derived exclusively from actual raw source witness, not candidate response or case id.",
    "unobserved": "Trusted profile cannot fabricate unobserved operands; source-input witnesses are finite profile evidence, not authentication or full native parity."
  },
  "timestamp_source_inputs": [
    {
      "raw_frame": "{\"type\":\"timestamp\",\"value\":\"2023-11-14T22:13:20.123456717Z\"}",
      "rawCanonical": "2023-11-14T22:13:20.123456717Z",
      "issue_payload": {
        "canonical": "2023-11-14T22:13:20.123456717Z",
        "reference_bits": "41c58214400fcd6e",
        "unix_bits": "41d954fc4007e6b7"
      },
      "source_witness_id": "timestamp-nine-representable",
      "input_only": true
    }
  ],
  "scanner_limit_contract": {
    "numeric_raw_token": "Count each complete syntactic JSON numeric token UTF8 bytes globally even ignored subtree;1024 admitted scanner,1025 private_value_limit before any Current/profile. Admission alone does not decide Foundation class; selected unwitnessed1024 token invokes explicit unavailable trusted profile once.",
    "decoded_key": "Each decoded key separately,8192 accepted/8193 private_value_limit. Escaped ASCII8192/8193 and multibyteé4096(+ASCIIa) exercise decodedUTF8 rather than raw lexeme/UTF16 length. Ignored nested keys included globally; key/payload not promoted to metadata or materialized native typed view.",
    "order": "Entire bounded syntactic preflight before captured Current/native effects; malformed syntax uses invalid_typed_value; globally oversized valid frames use private_value_limit. No unknown CodingKeys strictness or public/native history narrowing."
  },
  "stage1_review_correction_history": {
    "review": {
      "path": "/private/tmp/healthmd-query-typed-values-independent-review.json",
      "sha256": "24cc2cba135a6f1b92b0c89fe3608bd1c4ba1992300392718a9573d7a9a98b8c",
      "bytes": 7390
    },
    "archive": "/private/tmp/healthmd-query-typed-values-before-TV1-TV2-TV3",
    "before_vector": {
      "path": "packages/healthmd-core-ts/tests/query-typed-values-vectors.ts",
      "sha256": "2da36b45d3aa104f9ef19d94dcf1d41daa7ab59a2a827fc2b5a4e982e47d83f0",
      "bytes": 314765
    },
    "before_receipt": {
      "path": "docs/migration/effect-refactor/receipts/QUERY-TYPED-VALUES.json",
      "sha256": "8cdb64e122a22105adf30365ad2f2e328f6ff30b76a5774021e34226fc4bab5d",
      "bytes": 35454
    },
    "corrected_existing_case_ids": [
      "raw-byte-boundary",
      "string-byte-boundary",
      "depth-boundary",
      "node-boundary"
    ],
    "unchanged_old_cases": 110,
    "added_case_ids": [
      "numeric-token-selected-1024",
      "numeric-token-ignored-1024",
      "numeric-token-ignored-nested-1024",
      "numeric-token-selected-1025",
      "numeric-token-ignored-1025",
      "numeric-token-ignored-nested-1025",
      "decoded-key-ascii-8192",
      "decoded-key-ascii-8193",
      "decoded-key-escaped-8192",
      "decoded-key-escaped-8193",
      "decoded-key-multibyte-8192",
      "decoded-key-multibyte-8193",
      "decoded-key-ignored-nested-8192",
      "decoded-key-ignored-nested-8193"
    ],
    "timestamp_interface": "Explicit NativeTimestampInput canonical+optional independent finitebits, no native arithmetic recovery",
    "no_execution": true
  }
} as const;
