/** Stage1 literal-only contract. No candidate implementation, test or build executed. */
import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
declare const frameBrand: unique symbol;
declare const parsedBrand: unique symbol;
declare const parseErrorBrand: unique symbol;
declare const sessionBrand: unique symbol;
declare const outputBrand: unique symbol;
declare const leaseBrand: unique symbol;
declare const valueBrand: unique symbol;
declare const spanBrand: unique symbol;
declare const replyBrand: unique symbol;
export interface OwnedFrame { readonly [frameBrand]: true }
export interface OwnedParsed { readonly [parsedBrand]: true }
export interface OwnedSourceParseError { readonly [parseErrorBrand]: true }
export type OwnedInspectionOutcome = OwnedParsed | OwnedSourceParseError;
export interface OwnedSession { readonly [sessionBrand]: true }
export interface OwnedOutput { readonly [outputBrand]: true }
export interface OwnedLease { readonly [leaseBrand]: true }
export interface OwnedJson { readonly [valueBrand]: true }
export interface OwnedSpan { readonly [spanBrand]: true }
export interface OwnedReply { readonly [replyBrand]: true }
export type FixedFailure = { readonly code: "private_rpc_input" | "private_rpc_codec" | "private_rpc_dispatch" | "private_rpc_authority" | "private_rpc_busy" | "private_rpc_owned" | "private_rpc_cleanup" | "owned_handoff_closed" };
export type SourceNumber = { readonly kind: "signed_integer" | "unsigned_integer"; readonly decimal: string } | { readonly kind: "binary64"; readonly bits: string };
export type SourceValue = null | boolean | string | SourceNumber | readonly SourceValue[] | { readonly kind: "object"; readonly entries: readonly (readonly [string, SourceValue])[] };
export type SourceId = { readonly present: false } | { readonly present: true; readonly scalar: "string" | "signed_integer" | "unsigned_integer" | "binary64" | "invalid"; readonly canonicalEncoded: string; readonly validI64OrString: boolean };
export interface InspectionMetadata { readonly rootObject: boolean; readonly version2: boolean; readonly id: SourceId; readonly method: string | null; readonly params: OwnedSpan | null; readonly paramsDefaulted: boolean; readonly progressToken: OwnedSpan | null }
export interface CodecIssuer {
  inspection(primitiveMetadataWire: unknown, frame: OwnedFrame): OwnedParsed | null;
  /** Fixed source Parse error/null ID; no arbitrary code/cause/payload from parser. */
  sourceParseError(frame: OwnedFrame): OwnedSourceParseError | null;
  json(primitiveSourceValueWire: unknown): OwnedJson | null;
  encoded(primitiveUTF8Text: unknown, request: OwnedInspectionOutcome): OwnedOutput | null;
}
export interface LexicalView { frameText(frame: unknown): string | null }
export interface InertRequestView { inspect(request: unknown): InspectionMetadata | null }
export interface AuthorizedRequestView extends InertRequestView {
  /** Only granted current request spans; membership, Scope and permit checked on EACH read. */
  spanText(request: unknown, span: unknown): Effect.Effect<string | null, FixedFailure>;
}
export type ReplyView = { readonly kind: "success"; readonly idCanonicalEncoded: string; readonly result: OwnedJson } | { readonly kind: "error"; readonly idCanonicalEncoded: string; readonly code: number; readonly fixedMessage: string } | { readonly kind: "progress"; readonly notification: OwnedJson };
export interface OwnedValueView { readJson(value: unknown): SourceValue | null; inspectReply(reply: unknown): ReplyView | null }
export interface ExactScalarPort { render(representation: unknown, primitivePayload: unknown): unknown }
/** Pure trusted scalar renderer port: existing exact-number source is authoritative; no import
 * bypass, numeric algorithm duplication or current package export asserted. Separately admitted
 * real codec adapter wires this port; this child's fake serializer has fixed independent literals. */
export interface OwnedOutputView { encodedText(output: unknown): Effect.Effect<string | null, FixedFailure> }
export interface LosslessCodec {
  inspect(frame: OwnedFrame, issuer: CodecIssuer, view: LexicalView): unknown;
  serialize(request: OwnedInspectionOutcome, reply: OwnedReply, issuer: CodecIssuer, view: OwnedValueView): unknown;
}
export type AuthorityPhase = "before_materialization" | "before_allocation" | "before_progress" | "before_publication" | "assert_current";
export interface CurrentAuthority { check(request: OwnedParsed, phase: AuthorityPhase, view: InertRequestView): Effect.Effect<void, FixedFailure> }
export interface OperationIssuer {
  /** json ALWAYS issues a success-tagged value, including objects containing error/code/message. */
  json(primitiveSourceValueWire: unknown): OwnedJson | null;
  /** error issues a distinct private WeakMap tag with admitted fixed code/message; no JSON shape
   * examination may turn a success-tagged value into an error or authenticate arbitrary caller data. */
  error(code: unknown, fixedMessage: unknown): OwnedJson | null;
}
export interface FixedDispatcher {
  acquire(request: OwnedParsed, view: InertRequestView): Effect.Effect<unknown, FixedFailure>;
  release(allocationHandle: unknown): Effect.Effect<void, FixedFailure>;
  dispatch(request: OwnedParsed, lease: OwnedLease, emit: (progress: OwnedJson) => Effect.Effect<void, FixedFailure>, view: AuthorizedRequestView, issuer: OperationIssuer): Effect.Effect<OwnedJson, FixedFailure>;
}
export interface LocalMetadataPort {
  /** initialize/list tools/list resources/read resource use fixed common source metadata,
   * no acquired lease. Real schema/HTML/tool catalog adapters remain next owner. */
  describe(request: OwnedParsed, view: AuthorizedRequestView, issuer: OperationIssuer): Effect.Effect<OwnedJson, FixedFailure>;
}
export interface OwnedProgressSink { publish(output: OwnedOutput, view: OwnedOutputView): Effect.Effect<void, FixedFailure> }
export interface RpcEnvelope {
  open(): Effect.Effect<OwnedSession, FixedFailure, Scope.Scope>;
  handle(session: unknown, frame: unknown): Effect.Effect<OwnedOutput | null, FixedFailure>;
  encode(session: unknown, output: unknown): Effect.Effect<string, FixedFailure>;
  assertCurrent(session: unknown, output: unknown): Effect.Effect<void, FixedFailure>;
}
export interface TrustedFactoryInputs { readonly codec: LosslessCodec; readonly authority: CurrentAuthority; readonly dispatcher: FixedDispatcher; readonly metadata: LocalMetadataPort; readonly progress: OwnedProgressSink }
export interface RpcFactory { create(inputs: TrustedFactoryInputs): Effect.Effect<RpcEnvelope, FixedFailure, Scope.Scope> }
/** Trusted ports, never caller JSON, hold source semantics. Each issuer accepts only a bounded
 * primitive private wire; it does not reflect arbitrary objects and is invalidated when its
 * callback returns. Inspection issues frame-bound opaque spans without decoding params.
 * inspect returns only an OWN callback-issued OwnedInspectionOutcome: parsed or fixed source
 * parse error. The parse-error token is bound to this exact OwnedFrame/factory/original Scope;
 * serializer receives the same owned context with factory-issued ReplyView error/null ID.
 * Foreign, malformed or expired callback outcomes fail private_rpc_codec, never source parse
 * error. Closure after any callback wins before publication; no allocation/metadata/dispatch
 * follows owned source parse failure. Full serde parsing/numeric conversion/rendering remains
 * a separately admitted adapter.
 * Factory/session/request/output/issuer membership precedes properties, including every view.
 * Completed acquire handles are opaque and atomically registered with captured release; Scope
 * sentinel precedes first trusted callback. Current checks and liveness follow every callback,
 * pending allocation completion, prepublication and assertion. All views capture original Scope;
 * a new Scope/provided Layer cannot revive them. Dispatcher owns common semantics, no case-ID
 * response table or second evaluator. No trusted parser metadata authenticates caller grants.
 */
export const rpcEnvelopeFixture = {
  "source_revision": "ff72e1af486d1ace8106281abbe34b3dd3e21e60",
  "stage": "fixture_only_before_independent_review",
  "source_reconciliation": [
    {
      "path": "AGENTS.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 6129,
      "sha256": "563ac20e38bf5e62d636f5e3a4f15e1f8a0b4d96c67d8150de0badcf89bef456",
      "current_bytes": 6129,
      "current_sha256": "563ac20e38bf5e62d636f5e3a4f15e1f8a0b4d96c67d8150de0badcf89bef456",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "GLOSSARY.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 3868,
      "sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
      "current_bytes": 3868,
      "current_sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/architecture/javascript-unified-layer-research.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 13361,
      "sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
      "current_bytes": 13361,
      "current_sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 284562,
      "sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd",
      "current_bytes": 284562,
      "current_sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/core-cli.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 5578,
      "sha256": "4b33f46482c9c3fe26b50badc07a0a604e5c97345cb7f5eb6526580ced249749",
      "current_bytes": 5578,
      "current_sha256": "4b33f46482c9c3fe26b50badc07a0a604e5c97345cb7f5eb6526580ced249749",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/templates.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 10054,
      "sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
      "current_bytes": 10054,
      "current_sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/cli.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 347600,
      "sha256": "d013adcb657d2b190a75506ddef1adc85a3181c4eb3cf5180a8834789961fbe3",
      "current_bytes": 347600,
      "current_sha256": "d013adcb657d2b190a75506ddef1adc85a3181c4eb3cf5180a8834789961fbe3",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/inventories/core.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 95633,
      "sha256": "56536fc5f207a1f8508542ca98fd7d01cff3b882db002a3df8521bdb59d39ac7",
      "current_bytes": 95633,
      "current_sha256": "56536fc5f207a1f8508542ca98fd7d01cff3b882db002a3df8521bdb59d39ac7",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-CLI.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 12304,
      "sha256": "be25457e7c1672dfacc706702a47c762e3bb9781ecb978391412195247d824f1",
      "current_bytes": 12304,
      "current_sha256": "be25457e7c1672dfacc706702a47c762e3bb9781ecb978391412195247d824f1",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-CORE.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 26431,
      "sha256": "839b110fc881fdbf73d2bb9f06b6bab3f35c74eaf0f7c6f3d8d63d8b42c19c9a",
      "current_bytes": 26431,
      "current_sha256": "839b110fc881fdbf73d2bb9f06b6bab3f35c74eaf0f7c6f3d8d63d8b42c19c9a",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/expansions/split-protocol.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 145883,
      "sha256": "a0bbbf6ed6db434c957488fa37cb8ef9c92f3ac6334c0a63736c935034439c67",
      "current_bytes": 145883,
      "current_sha256": "a0bbbf6ed6db434c957488fa37cb8ef9c92f3ac6334c0a63736c935034439c67",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/SPLIT-PROTOCOL.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 33855,
      "sha256": "6ba1dbaed77ed7a024f94ed7b008b6c0001b1cabf7e493d66dfa7cb298f8620d",
      "current_bytes": 33855,
      "current_sha256": "6ba1dbaed77ed7a024f94ed7b008b6c0001b1cabf7e493d66dfa7cb298f8620d",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/SLICE-PARITY.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 27886,
      "sha256": "c8f395b086606b685c3f539d105a74036a4f42608534a1eb80d11c2ecf67a4f4",
      "current_bytes": 27886,
      "current_sha256": "c8f395b086606b685c3f539d105a74036a4f42608534a1eb80d11c2ecf67a4f4",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/cohorts/core-ts-personal-slices-v1.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 34945,
      "sha256": "1dbee84851fb08b26a66d436014496f097fc94fafeeef880846897ca13ba4853",
      "current_bytes": 34945,
      "current_sha256": "1dbee84851fb08b26a66d436014496f097fc94fafeeef880846897ca13ba4853",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CORE-COHORT-PERSONAL-SLICES.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 124059,
      "sha256": "faaa45e7d1d19a2cd4b69eec7f05d29bd332a4beacc1fcff36111259a462c602",
      "current_bytes": 124059,
      "current_sha256": "faaa45e7d1d19a2cd4b69eec7f05d29bd332a4beacc1fcff36111259a462c602",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "docs/migration/effect-refactor/expansions/split-usage-desktop.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 139864,
      "sha256": "8aeedc538783d9e0373adec386f0bd9f1ce7a92c8a368c3d6ab2711e7ce2097f",
      "current_bytes": 139864,
      "current_sha256": "8aeedc538783d9e0373adec386f0bd9f1ce7a92c8a368c3d6ab2711e7ce2097f",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "packages/healthmd-core-ts/AGENTS.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 860,
      "sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
      "current_bytes": 860,
      "current_sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/docs/typescript-candidate.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 7580,
      "sha256": "1b7898390cf04c276a285b60fee5c09215640ca95618b94c9abb73f756c3490b",
      "current_bytes": 9517,
      "current_sha256": "cfd673b889af17653694ca48bd5947f86e686b0a20260c10eab63716344b68c9",
      "current_matches_assigned_git": true,
      "historical_unchanged": false
    },
    {
      "path": "apps/cli/package.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 880,
      "sha256": "baa07d8b88444ac74a7de411384e5ee84133a90f91fa255bf07c3fc0d61c9fd2",
      "current_bytes": 880,
      "current_sha256": "baa07d8b88444ac74a7de411384e5ee84133a90f91fa255bf07c3fc0d61c9fd2",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/package-lock.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 28291,
      "sha256": "3be9fb54116c58d89421e7bd43d2f5c5bb4b0f98f818a0ef3ba18c77f4903cbf",
      "current_bytes": 28291,
      "current_sha256": "3be9fb54116c58d89421e7bd43d2f5c5bb4b0f98f818a0ef3ba18c77f4903cbf",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/scripts/build-candidate.mjs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 1574,
      "sha256": "0f4bd85e16b9462d265a370ec132c27b9655c21e22e634c68545e5e4ee70bcfa",
      "current_bytes": 1574,
      "current_sha256": "0f4bd85e16b9462d265a370ec132c27b9655c21e22e634c68545e5e4ee70bcfa",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/scripts/check-candidate.mjs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 35746,
      "sha256": "aca2e32e0047fc397c9bde572f3464b17a4482589d6a1a986a6b0bda3efd8de3",
      "current_bytes": 48837,
      "current_sha256": "04a26fccd1b2c32976d18995ca161507ceeafa24c34dbae93e15927726332794",
      "current_matches_assigned_git": true,
      "historical_unchanged": false
    },
    {
      "path": "apps/cli/tsconfig.build.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 144,
      "sha256": "2f9f05c0822a03a2e63d07171e58988d39c55be6582c562f36e5b85690d1e42b",
      "current_bytes": 144,
      "current_sha256": "2f9f05c0822a03a2e63d07171e58988d39c55be6582c562f36e5b85690d1e42b",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/tsconfig.test.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 123,
      "sha256": "db9dfadaa7870e3134056444efbe00eaf427c8ee0ed43f6369cbcfd61c39b4c0",
      "current_bytes": 123,
      "current_sha256": "db9dfadaa7870e3134056444efbe00eaf427c8ee0ed43f6369cbcfd61c39b4c0",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-cli/src/main.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 110543,
      "sha256": "7f6be243c49085ea188adf739b829d968d8330b196a7e2317a043d4a8e2ddf32",
      "current_bytes": 110543,
      "current_sha256": "7f6be243c49085ea188adf739b829d968d8330b196a7e2317a043d4a8e2ddf32",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-cli/src/guidance.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 42824,
      "sha256": "f71d47555df981fbbc27f70bec6746a40846b6287f3f1200f2d9a6aac95456e0",
      "current_bytes": 42824,
      "current_sha256": "f71d47555df981fbbc27f70bec6746a40846b6287f3f1200f2d9a6aac95456e0",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-cli/src/mcp/mod.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 27301,
      "sha256": "2d727be8830adfe639faa536b875b0f0ac91690de7872d233577b0fccead6fa0",
      "current_bytes": 27301,
      "current_sha256": "2d727be8830adfe639faa536b875b0f0ac91690de7872d233577b0fccead6fa0",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 17008,
      "sha256": "b7082b9dc860f5b20509ae0517bb76db2f6cb29d06525e463ac4342b081284ae",
      "current_bytes": 17008,
      "current_sha256": "b7082b9dc860f5b20509ae0517bb76db2f6cb29d06525e463ac4342b081284ae",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-cli/src/output.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 29781,
      "sha256": "7ffedba6a33ee4111a993c5b6091da1b309d6e3ccc02d7a3ed64374b42e62afb",
      "current_bytes": 29781,
      "current_sha256": "7ffedba6a33ee4111a993c5b6091da1b309d6e3ccc02d7a3ed64374b42e62afb",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-cli/src/onboarding.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 17363,
      "sha256": "ea1cc76fdb08f44bfba6f482e079cd121ffe6c2a49636470f919aa7bd51c7eba",
      "current_bytes": 17363,
      "current_sha256": "ea1cc76fdb08f44bfba6f482e079cd121ffe6c2a49636470f919aa7bd51c7eba",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/result.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 2531,
      "sha256": "2d56e254c0af85537eca102adebaf1140fc9c77ceea0b9f1a881800f73b1d28f",
      "current_bytes": 2531,
      "current_sha256": "2d56e254c0af85537eca102adebaf1140fc9c77ceea0b9f1a881800f73b1d28f",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-operations/src/registry.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 52174,
      "sha256": "0d16820bf891bd5ac71741f7ac955887c3be289201a01893100f1886f3a2a827",
      "current_bytes": 52174,
      "current_sha256": "0d16820bf891bd5ac71741f7ac955887c3be289201a01893100f1886f3a2a827",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/application.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 58209,
      "sha256": "989bfd02c8c243237628343cf4500a07cce3731facb00565735ef35863657d8a",
      "current_bytes": 58209,
      "current_sha256": "989bfd02c8c243237628343cf4500a07cce3731facb00565735ef35863657d8a",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-operations/src/model.rs",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 1129,
      "sha256": "a60a1163ab5861ce062d010045e2e6bad8f1c6fccbea2094ead3f0c0980850ad",
      "current_bytes": 1129,
      "current_sha256": "a60a1163ab5861ce062d010045e2e6bad8f1c6fccbea2094ead3f0c0980850ad",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/src/cli/query.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 7155,
      "sha256": "a7b83690886d6d643ce5a72f98514739eadb6a34178148ad6111c7caf50d98a2",
      "current_bytes": 7155,
      "current_sha256": "a7b83690886d6d643ce5a72f98514739eadb6a34178148ad6111c7caf50d98a2",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/src/mcp/query.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 6487,
      "sha256": "97ba3ed0c2a0c60872ce3a6eda757e8ecc08f9391848a74bb06c2be7ea2b50b9",
      "current_bytes": 6487,
      "current_sha256": "97ba3ed0c2a0c60872ce3a6eda757e8ecc08f9391848a74bb06c2be7ea2b50b9",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "packages/healthmd-core-ts/src/operations/normalize.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 2808,
      "sha256": "bfa2b22abba44e22bbfc60d50dac8df5654acf3f296b49b59ed812d8cd11fa45",
      "current_bytes": 2808,
      "current_sha256": "bfa2b22abba44e22bbfc60d50dac8df5654acf3f296b49b59ed812d8cd11fa45",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "packages/healthmd-core-ts/src/operations/query.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 8929,
      "sha256": "143c5a9c123a1febe0ac67b6fd46eefb578e669f8263aec11e2b553544add100",
      "current_bytes": 8929,
      "current_sha256": "143c5a9c123a1febe0ac67b6fd46eefb578e669f8263aec11e2b553544add100",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 116261,
      "sha256": "31377cf8ac0494d8410a2bd9cf69be0c65d1f0394517730e960f0f9a9016f52d",
      "current_bytes": 116261,
      "current_sha256": "31377cf8ac0494d8410a2bd9cf69be0c65d1f0394517730e960f0f9a9016f52d",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/tests/cli-query-vectors.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 4412,
      "sha256": "315098960cd4b7afdccd9c8d19a9f330495e33940f5954f4ea3026921b1f3bd2",
      "current_bytes": 4412,
      "current_sha256": "315098960cd4b7afdccd9c8d19a9f330495e33940f5954f4ea3026921b1f3bd2",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/tests/mcp-query-vectors.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 3586,
      "sha256": "4fddfa0b53eba0402bde2239b995bde2ea1e019f7f1076041b8dcc963df6b154",
      "current_bytes": 3586,
      "current_sha256": "4fddfa0b53eba0402bde2239b995bde2ea1e019f7f1076041b8dcc963df6b154",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    },
    {
      "path": "apps/cli/tests/candidate-api-vectors.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "bytes": 3176,
      "sha256": "e866e706c0cb71c4d782f5c9bcc9e12059f86897e7974cce60844c2c0a3f0cc6",
      "current_bytes": 3176,
      "current_sha256": "e866e706c0cb71c4d782f5c9bcc9e12059f86897e7974cce60844c2c0a3f0cc6",
      "current_matches_assigned_git": true,
      "historical_unchanged": true
    }
  ],
  "minimum_packet_case_ids": [
    "rpc-ping-exact-bytes",
    "rpc-parse-error-exact-bytes",
    "rpc-i64-id-lossless",
    "rpc-fraction-id-invalid",
    "rpc-encoded-id-bound",
    "rpc-outer-unknown-field-policy",
    "rpc-notification-no-response"
  ],
  "private_policy": {
    "frame_UTF8_bytes": 65536,
    "depth": 32,
    "nodes": 4096,
    "number_token_bytes": 256,
    "string_UTF8_bytes": 32768,
    "owned_response_UTF8_bytes": 262144,
    "progress_queue": 16,
    "one_busy_request": true,
    "public_limit_claim": false,
    "source_request_ID_canonical_bytes": 128,
    "source_lifetime_used_IDs": 16384,
    "source_duplicate_decoded_keys": "last_value",
    "source_outer_unknown_fields": "ignored",
    "budget_status": "Synthetic unmeasured private seam bounds, not public stdio/HTTP limits.",
    "transport_HTTP_public_UTF8_bytes": 2097152,
    "transport_bound_owner": "apps/cli/crates/healthmd-mcp/src/transport/streamable_http.rs:25; separate transport owner, not this64KiB private frame gate"
  },
  "contract": {
    "lossless_parser": "Trusted semantic adapter receives already primitive bounded JSON grammar and raw numeric lexemes. Own issuer returns opaque inspection, inert method/ID canonical encoded metadata and opaque unmaterialized params span tied to exact original frame. IDs classify serdeI64/U64/F64/String; never Number.isInteger. Raw -0 is F64 negativezero. Complete parser numerical conversion source feature graph remains next owner. Parser/issuer authenticity is NOT caller authentication.",
    "serializer": "Trusted source-semantic adapter, own issued encoded primitive, no JSON.stringify numeric assumption. Existing exact scalar implementation is pinned but NOT currently a package export. Full future codec adapter must reuse/admit it separately; this bounded child does not implement a numeric renderer. Source BTreeMap key order, source escaping and canonical tokens are frozen independently. Returned primitive bytes bound to own request, captured Scope and current authority. Full serializer/tool/HTML grammar next owner.",
    "authority": "Trusted per-request current caller/source/purpose/recipient/grant/catalog plus latest external suppression/frontier service captured at factory Scope. No selfclaimed JSON booleans. Inert metadata check before params materialization/allocation, recheck after callbacks, progress and final publication/assertCurrent. Pure ping/local failures/notifications acquire0, never source calls.",
    "dispatcher": "Fixed common operation port, application metadata and result grammar remain external common authority; fake owns synthetic allocation/results not evaluator. No caseID table in implementation.",
    "ownership": "Factory-issued WeakMap request/session/codec/result and WeakSet output membership before properties. Unknown primitive frame admitted before callback/coercion. Factory/session/lease bound original Scope, live sentinel registered before FIRST trusted callback. Check after every trusted callback and completedallocation, before progress/final publication/assertCurrent; newScope or providedLayer cannot revive closed session. One in-flight private request; completedresource allocation+finalizer atomic, asyncreleaseACK awaited before handoff; failures poison lifetime.",
    "cancellation": "Interrupt/EOF signals owned operation, await exact once finalizerACK. Never pretend possible externalcommit rolledback; actual transport sessions/slow pipe/process cancellation deferred. Cause stripped to fixed failures or interrupt-only IDs without provider reasons.",
    "progress": "Source valid token string rawUTF8<=128 or exacti64, not requestIDcanonical<=128;16sourcechannel slots. Fake bounded owned async sink, backpressure/interrupt/finalizer lifetime explicit; only currentpermit then materialize canonical notification. No real transport qualification.",
    "used_ids": "Canonical encoded ID key strings andnumbers distinct; permanent session set on syntactically validrequest beforemethoddispatch, unknown/unsupported/errors consume; invalidIDs/notifications do not. Duplicate before16384limit precedence.",
    "wire_grammar": {
      "inspection": "Primitive JSON object exactly rootObject:boolean,version2:boolean,id:closed union,method:string|null,params:span|null,paramsDefaulted:boolean,progressToken:span|null. id absent={present:false}; present={present:true,scalar:enum,canonicalEncoded:string,validI64OrString:boolean}. span={start:canonical nonnegative integer,end:canonical nonnegative integer} in original UTF16 frame bounds and complete lexical value boundary. No offsets accepted from caller JSON as authority. Issuer owns spans and frozen metadata. Closed key policy, no duplicate private descriptor keys. Canonical JSON integer tokens before Number conversion; raw descriptor bound64KiB/depth32/nodes4096.",
      "value": "Primitive JSON SourceValue wire tagged number with canonical decimal or16-lowerhex finitebits; object tagged {kind:object,entries:[[string,SourceValue],...]}; source semantic adapter, not arbitrary caller-object conversion. Frozen views and arrays factory-owned.",
      "error": "OperationIssuer.error only canonical exact integer fixed source error codes and admitted fixed messages in this fixture; no provider text.",
      "encoding": "Bounded primitive JSON text checked independently for grammar/UTF8/scalars before issuance, encoded origin bound to request. No source-parity assertion inferred from trusted output grammar."
    },
    "local_methods": "Factory owns protocol decision order, IDs and local ping/errors. Initialize and catalog/resources receive trusted source metadata adapter results with no resource acquire; exact current source information is fixture-bound. Full application/catalog rendering remains next owner. Notifications return null only after JSON/root/version/method validation. No initialize-before-ping policy. LocalMetadataPort.describe supplies owned result/error for recognized metadata methods without acquire; factory source method map owns routing. Codec serialize receives OwnedReply plus frozen ReplyView so source success/error/progress shape cannot be inferred from untrusted JSON keys. Pure current metadata is authorized separately from tool payloads; no data grant/network/source acquisition.",
    "callback_safety": "All unknown session/frame/output and returned codec values checked by primitive typeof or own membership BEFORE any property/coercion/callback. TrustedFactoryInputs is host-owned configuration, never parsed from caller JSON. Sentinel registered at factory/open before trusted callbacks. Per-callback issuer lifetime prevents escaped/reentered issuance. Caller-derived opaque IDs/methods/params are request data only.",
    "scalar_port": "ExactScalarPort.render unknown primitives only; authoritative existing implementation pinned, no current export/import. Adapter admission concrete SPLIT-CODECS child before real MCP/public serializer promotion; fake canonical-byte literals only.",
    "malformed_frame": "Primitive/scalar/UTF8/private budget gate failure => fixed private_rpc_input before trusted callbacks. Well-bounded primitive JSON syntax failure => same own fixed source Parse error/null-ID context; lone surrogate escape is source parse failure. Syntactically valid JSON numerical overflow anywhere may be source_parse_error supplied by separately owned lossless adapter before root/version/ID validation. Raw illformed UTF16 => private frame failure, not full source framing equivalence. Unknown key content structurally scanned under budgets but ignored semantically only AFTER source semantic parse; duplicate decoded keys last value. No full JSON.parse params materialization or new numeric parser algorithm.",
    "closed_failure_precedence": "Unknown primitive/membership first, original closed Scope next, busy then structural/private gates, source parse/root/version/method/id/duplicate/session-limit order. OriginalScope closure observed after trusted callback takes owned_handoff_closed precedence over returned success/metadata. Cleanup failure poisons session with private_rpc_cleanup, ACK awaited; no successful response is publishable after observed closure.",
    "canonical_source_scope": "Locked cached serde_json1.0.151 source policies plus explicit current Cargo declarations support these independently derived literals. Fully resolved feature closure and complete floating lexeme conversion remain future adapter qualification. No actual Rust/native execution, no candidate output generated expectations. Unicode object sort uses scalar/UTF8 order, not JS UTF16 sort.",
    "parser_outcome": "LosslessCodec.inspect returns unknown to the factory; runtime acceptance is ONLY current callback-issued OwnedInspectionOutcome tagged parsed OR source_parse_error, bound by own WeakMap to exact OwnedFrame/factory/original Scope and issuer lifetime. CodecIssuer.sourceParseError accepts only this owned frame and issues fixed Parse error/-32700/null-ID context. No arbitrary parser code/message/cause accepted. Foreign/malformed/expired/Proxy outcomes fail private_rpc_codec with zero property effects. Check original Scope after callback before recognizing either outcome; closed wins owned_handoff_closed. Source parse error short-circuits version/root/method/ID/used-ID/metadata/current-resource/dispatch/allocation; serializer receives same owned parse context and factory-owned error ReplyView with idCanonicalEncoded null. Source invalid JSON syntax may use same factory-issued source-error context after private raw budget/scalar gate; numeric overflow in any syntactically valid field is source semantic parse failure before protocol validation, not private codec or root invalid request.",
    "operation_error_tag": "OperationIssuer.json(primitive SourceValue wire) privately tags every minted OwnedJson as SUCCESS, including objects with error/code/message keys. OperationIssuer.error(admitted fixed code,message) privately tags another own value as ERROR in a WeakMap bound to current callback/request/factory/Scope. Factory constructs OwnedReply by this private issuance tag only; source JSON-shaped result never determines failure disposition. Serializer receives own frozen ReplyView success/error/progress discriminator after membership checks. Expired/foreign issuance stays private boundary failure. Frozen root contrast cases show same error-shaped content in success result vs fixed RPC error envelope.",
    "port_counters": "dispatch_calls counts ONLY FixedDispatcher.dispatch for acquired common synthetic operation; metadata_calls counts ONLY LocalMetadataPort.describe for source initialize/catalog/resource metadata with acquire0; parser/serializer/current authority tracked separately in lifetime stimuli. Each initialize protocol/UI/unsupported case describes once, dispatcher0, allocation/release0. Source response bytes unchanged."
  },
  "remaining_qualification": [
    {
      "id": "SPLIT-CODECS/MCP-SERDE-CODEC-ADAPTER",
      "owner": "core_cli coordinator and separately claimed SPLIT-CODECS numeric/parser/package-admission child",
      "trigger": "Before a real source-semantic parser/serializer adapter, public MCP byte-parity claim, numeric renderer import, or package/consumer promotion; separately accepted SPLIT-CODECS child and cohort proof first.",
      "proof": "Exact locked serde_json feature/POMsource profile; bounded Unicode/duplicate/finitef64 decimal parser and source serializer equivalence; admitted exactnumber renderer reused; not fake metadata authenticity. Exact scalar implementation is currently NOT a package export; explicitly admit reuse before real adapter. No guessed import."
    },
    {
      "id": "MCP-COMMON-APPLICATION-RESULT",
      "owner": "common operations coordinator / CLI-RESULT-ENVELOPE",
      "trigger": "before realtools/resources/results/schema/progress renderer",
      "proof": "Full21/13catalog andschemas, tool result/query/export/images/HTML source, authenticatedcurrentperpagegrant andlatestfrontier; no fake health/native evaluator."
    },
    {
      "id": "MCP-TRANSPORT-LIFETIME",
      "owner": "core_cli transport owner",
      "trigger": "before actualstdio/HTTP/client launch",
      "proof": "Boundedframing/backpressure/EOF/ownedprocess/session/perrequestOAuth/OSidentity/currentauthority/nativecleanup/durableambiguity."
    }
  ],
  "cases": [
    {
      "case_id": "rpc-ping-exact-bytes",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "rpc-parse-error-exact-bytes",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "rpc-i64-id-lossless",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":9223372036854775807,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":9223372036854775807,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "rpc-fraction-id-invalid",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1.0,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":1.0,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "rpc-encoded-id-bound",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "packet_metadata_reconciliation": "Original literal is127ASCII ID; packet id_raw_utf8_bytes129 is canonical encoded length includingquotes, not actualraw length. Retain literal/negative expectation; correct descriptor distinction."
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "encoded_id_bytes": 129,
        "health_or_provider_echo": false,
        "raw_id_UTF8_bytes": 127,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "rpc-outer-unknown-field-policy",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"extra\":true}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "rpc-notification-no-response",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "notification",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "min-i64",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":-9223372036854775808,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":-9223372036854775808,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "positive-zero",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":0,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "string-one",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":\"1\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "empty-string",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":\"\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "unicode-string",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\u00e9\ud83d\ude00\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":\"\u00e9\ud83d\ude00\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "escaped-astral",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\\ud83d\\ude00\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":\"\ud83d\ude00\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "escaped-slash",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"a\\/b\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":\"a/b\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "exponent-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1e0,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":1.0,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "negative-zero-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":-0,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":-0.0,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "u64-not-i64",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":9223372036854775808,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":9223372036854775808,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "fraction-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1.5,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":1.5,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "null-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "boolean-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":true,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":true,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "array-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":[],\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":[],\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "object-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":{\"z\":1,\"a\":2},\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":{\"a\":2,\"z\":1},\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "root-array",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "[]",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "root-null",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "null",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "root-string",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "\"x\"",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "root-number",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "1",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "missing-version",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "wrong-version",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "missing-method-echoes-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "nonstring-method-before-id-validity",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":1}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":{},\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "missing-method-not-notification",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "ping-notification",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "notification",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "unknown-notification",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"method\":\"private_method\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "notification",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "tool-notification",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "notification",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "duplicate-last-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":2,\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "escaped-duplicate-last-id",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":2,\"\\u0069d\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "duplicate-last-method",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"bad\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "duplicate-last-version",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"bad\",\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "non-object-ping-params",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":null}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "params-unknown-ignored",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"private\":true}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "duplicate-last-version-invalid",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"jsonrpc\":\"bad\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "leadingzero",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":01,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "trailing-garbage",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}x",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "nonJSON-NaN",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":NaN,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "unterminated-string",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"x}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "lone-surrogate-escape",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\\ud800\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "encoded-ascii-126",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "encoded_id_bytes": 128,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "encoded-ascii-127",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "encoded_id_bytes": 129,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "encoded-NUL-21",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "encoded_id_bytes": 128,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "encoded-NUL-22",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\",\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "encoded_id_bytes": 134,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "duplicate-reuse",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_before": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
            "expected_response": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Duplicate request identifier\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "used_IDs_final": 1,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "numeric-and-string-distinct",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_before": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
            "expected_response": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":\"1\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "used_IDs_final": 2,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "session-ID-budget",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "seed_by_real_successful_handle_calls": {
              "first_integer_id": 2,
              "last_integer_id": 16385,
              "method": "ping"
            },
            "no_internal_used_set_mutation": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32001,\"message\":\"Session request limit exceeded\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "used_IDs_final": 16384,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "unknown-method-no-echo",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"private_method\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "used_IDs_final": 1,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "resources-disabled",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/list\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "initialize-unsupported",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "local_metadata_port": "source initialize metadata outcome, no acquired lease"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32602,\"message\":\"Unsupported MCP protocol version\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 1
      }
    },
    {
      "case_id": "initialize-2024-11-05",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "local_metadata_port": "source initialize metadata outcome, no acquired lease"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"capabilities\":{\"tools\":{\"listChanged\":false}},\"instructions\":\"Use this remote read-only Health.md surface for readiness and typed queries only. Pairing and file-export tools are unavailable; the server operator must pair its iPhone source outside MCP. Keep Health.md foreground on the paired iPhone. Prefer healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Every query is live; there is no synchronized health-data corpus or fallback.\",\"protocolVersion\":\"2024-11-05\",\"serverInfo\":{\"name\":\"healthmd-mcp\",\"version\":\"0.1.0-alpha.7\"}}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "application_metadata_only": true,
        "health_or_provider_echo": false,
        "metadata_calls": 1
      }
    },
    {
      "case_id": "initialize-2025-03-26",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "local_metadata_port": "source initialize metadata outcome, no acquired lease"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"capabilities\":{\"tools\":{\"listChanged\":false}},\"instructions\":\"Use this remote read-only Health.md surface for readiness and typed queries only. Pairing and file-export tools are unavailable; the server operator must pair its iPhone source outside MCP. Keep Health.md foreground on the paired iPhone. Prefer healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Every query is live; there is no synchronized health-data corpus or fallback.\",\"protocolVersion\":\"2025-03-26\",\"serverInfo\":{\"name\":\"healthmd-mcp\",\"version\":\"0.1.0-alpha.7\"}}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "application_metadata_only": true,
        "health_or_provider_echo": false,
        "metadata_calls": 1
      }
    },
    {
      "case_id": "initialize-2025-06-18",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "local_metadata_port": "source initialize metadata outcome, no acquired lease"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"capabilities\":{\"tools\":{\"listChanged\":false}},\"instructions\":\"Use this remote read-only Health.md surface for readiness and typed queries only. Pairing and file-export tools are unavailable; the server operator must pair its iPhone source outside MCP. Keep Health.md foreground on the paired iPhone. Prefer healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Every query is live; there is no synchronized health-data corpus or fallback.\",\"protocolVersion\":\"2025-06-18\",\"serverInfo\":{\"name\":\"healthmd-mcp\",\"version\":\"0.1.0-alpha.7\"}}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "application_metadata_only": true,
        "health_or_provider_echo": false,
        "metadata_calls": 1
      }
    },
    {
      "case_id": "initialize-2025-11-25",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "local_metadata_port": "source initialize metadata outcome, no acquired lease"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"capabilities\":{\"tools\":{\"listChanged\":false}},\"instructions\":\"Use this remote read-only Health.md surface for readiness and typed queries only. Pairing and file-export tools are unavailable; the server operator must pair its iPhone source outside MCP. Keep Health.md foreground on the paired iPhone. Prefer healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Every query is live; there is no synchronized health-data corpus or fallback.\",\"protocolVersion\":\"2025-11-25\",\"serverInfo\":{\"name\":\"healthmd-mcp\",\"version\":\"0.1.0-alpha.7\"}}}",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "application_metadata_only": true,
        "health_or_provider_echo": false,
        "metadata_calls": 1
      }
    },
    {
      "case_id": "tool-unknown",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_fixed_error": {
              "code": -32602,
              "message": "Unknown tool"
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32602,\"message\":\"Unknown tool\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "tool-args-invalid",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_fixed_error": {
              "code": -32602,
              "message": "Invalid tool arguments"
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32602,\"message\":\"Invalid tool arguments\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "tool-readscope-denied",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_fixed_error": {
              "code": -32003,
              "message": "The caller lacks the required Health.md read scope."
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32003,\"message\":\"The caller lacks the required Health.md read scope.\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "tool-success-text-envelope",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "arguments_materialized_after_authority": true,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "progress-fixed-source-shape",
      "basis": "retained jsonrpc.rs control flow; serde_json1.0.151 source semantics",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"_meta\":{\"progressToken\":\"wake-7\"}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}",
            "progress": {
              "progress": 10,
              "total": 120,
              "message": "Waiting for the paired source."
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":7,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "progress_utf8": [
          "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"message\":\"Waiting for the paired source.\",\"progress\":10,\"progressToken\":\"wake-7\",\"total\":120}}"
        ],
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "frame-proxy",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "frame_override": {
              "kind": "Proxy",
              "target": "empty_object",
              "traps": "all_throw_and_count"
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_input",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "frame-coercion",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "frame_override": {
              "kind": "object",
              "toString": "throw_and_count",
              "valueOf": "throw_and_count",
              "symbolToPrimitive": "throw_and_count"
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_input",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "raw-lone-surrogate",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "frame_override": {
              "kind": "primitive_UTF16_code_units",
              "units": [
                55296
              ]
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_input",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "frame-over64KiB",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "frame_override": {
              "kind": "repeat_ASCII",
              "character": " ",
              "count": 65537
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_input",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "depth-over32",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "frame_override": {
              "kind": "nested_array_literal",
              "array_levels": 33,
              "leaf": "0"
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_input",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "nodes-over4096",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "frame_override": {
              "kind": "flat_array_literal",
              "element": "0",
              "element_count": 4096
            }
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_input",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "codec-proxy-result",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "codec_return": "foreign_Proxy_all_traps_throw_count"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "codec-foreign-result",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "codec_return": "owned_inspection_from_other_factory"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "serializer-proxy-result",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "serializer_return": "foreign_Proxy_all_traps_throw_count"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "dispatcher-provider-defect",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatch_action": "die_with_private_sentinel",
            "sentinel": "PRIVATE_DO_NOT_ECHO"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_dispatch",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "authority-denied",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "authority_action": "fixed_denial",
            "phase": "before_materialization"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_authority",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "authority-unavailable",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "authority_action": "fixed_unavailable",
            "phase": "before_materialization"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_authority",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "busy-session",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "start_first_handle": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
            "pause_at": "dispatch_pending",
            "invoke_second_handle": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_busy",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "foreign-session",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "session_override": "other_factory_owned_session"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_owned",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "encoder-proxy",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "encode_output_override": "foreign_Proxy_all_traps_throw_count"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_owned",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "encoder-foreign-output",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "encode_output_override": "other_factory_owned_output"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_owned",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cleanup-failed-poison",
      "basis": "new private synthetic interface policy; not source public wire behavior",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "release_action": "fail_fixed_cleanup",
            "then": "same_session_handle_again"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_cleanup",
        "release_attempts": 1,
        "session_poisoned": true,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-scope-already-closed",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "before_handle",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-parser-callback",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "parser-callback",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-authority-before-allocation",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "authority-before-allocation",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-allocator-return",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "allocator-return",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-dispatcher-callback",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "dispatcher-callback",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-authority-before-publication",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "authority-before-publication",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-serializer-callback",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "serializer-callback",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-progress-sink-callback",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"_meta\":{\"progressToken\":7}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "progress-sink-callback",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-assert-current-callback",
      "basis": "private original Scope sentinel requirement; independent IOS learned closure cases",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_to_owned_output_without_encode": true
          },
          {
            "close_original_scope": "assert-current-callback",
            "wait_release_ACK": true,
            "callback_returns_normally": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "callbacks_after_close": 0,
        "health_or_provider_echo": false,
        "handle_response_before_assertion": "owned_unpublished_output",
        "assert_current_result": "owned_handoff_closed",
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cancel-before-callback",
      "basis": "private async cancellation/lifetime contract; not peer/process OS cancellation proof",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "interrupt_owned_fiber_at": "before-callback",
            "wait_release_ACK": true,
            "no_OS_or_remote_cancel_claim": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "interrupted",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "publication_calls": 0,
        "provider_cause_disclosed": false,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cancel-pending-acquire",
      "basis": "private async cancellation/lifetime contract; not peer/process OS cancellation proof",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "interrupt_owned_fiber_at": "pending-acquire",
            "wait_release_ACK": true,
            "no_OS_or_remote_cancel_claim": true,
            "allocator_never_completes": "interruptible_deferred_no_resource_created"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "interrupted",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "publication_calls": 0,
        "provider_cause_disclosed": false,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cancel-after-allocation",
      "basis": "private async cancellation/lifetime contract; not peer/process OS cancellation proof",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "interrupt_owned_fiber_at": "after-allocation",
            "wait_release_ACK": true,
            "no_OS_or_remote_cancel_claim": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "interrupted",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "publication_calls": 0,
        "provider_cause_disclosed": false,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cancel-dispatch-pending",
      "basis": "private async cancellation/lifetime contract; not peer/process OS cancellation proof",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "interrupt_owned_fiber_at": "dispatch-pending",
            "wait_release_ACK": true,
            "no_OS_or_remote_cancel_claim": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "interrupted",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "publication_calls": 0,
        "provider_cause_disclosed": false,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cancel-progress-backpressure",
      "basis": "private async cancellation/lifetime contract; not peer/process OS cancellation proof",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"_meta\":{\"progressToken\":7}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "interrupt_owned_fiber_at": "progress-backpressure",
            "wait_release_ACK": true,
            "no_OS_or_remote_cancel_claim": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "interrupted",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "publication_calls": 0,
        "provider_cause_disclosed": false,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cancel-EOF",
      "basis": "private async cancellation/lifetime contract; not peer/process OS cancellation proof",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "interrupt_owned_fiber_at": "EOF",
            "wait_release_ACK": true,
            "no_OS_or_remote_cancel_claim": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "interrupted",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "publication_calls": 0,
        "provider_cause_disclosed": false,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cancel-new-scope-reprovided-layer",
      "basis": "private async cancellation/lifetime contract; not peer/process OS cancellation proof",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": true
          },
          {
            "handle_original_session_under": "new_scope_with_reprovided_services"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "publication_calls": 0,
        "provider_cause_disclosed": false,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "numeric-zero-string-zero-distinct",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_before": "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"ping\"}",
            "response_utf8": "{\"id\":0,\"jsonrpc\":\"2.0\",\"result\":{}}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":\"0\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "escaped-canonical-ID-reuse",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_before": "{\"jsonrpc\":\"2.0\",\"id\":\"\\u0061\",\"method\":\"ping\"}",
            "response_utf8": "{\"id\":\"a\",\"jsonrpc\":\"2.0\",\"result\":{}}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Duplicate request identifier\"},\"id\":\"a\",\"jsonrpc\":\"2.0\"}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "wrong-version-not-notification",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"1.0\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "missing-method-float-echo",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1.0}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":1.0,\"jsonrpc\":\"2.0\"}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "unknown-nested-fields-ignored",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"outer\":{\"id\":false,\"method\":[],\"nested\":[null,{\"id\":1.0}]}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "duplicate-escaped-method-last",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"bad\",\"m\\u0065thod\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "ID-limit-duplicate-precedence",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "seed_by_real_successful_handle_calls": {
              "first_integer_id": 1,
              "last_integer_id": 16384,
              "method": "ping"
            },
            "no_internal_used_set_mutation": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Duplicate request identifier\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "ID-limit-separate-session",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "open_session": "other"
          },
          {
            "seed_by_real_successful_handle_calls": {
              "session": "other",
              "first_integer_id": 1,
              "last_integer_id": 16384,
              "method": "ping"
            }
          },
          {
            "open_session": "target"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "unsupported-method-consumes-ID",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_before": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"unknown\"}",
            "response_utf8": "{\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":1,\"jsonrpc\":\"2.0\"}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Duplicate request identifier\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "invalid-ID-does-not-consume",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_before": "{\"jsonrpc\":\"2.0\",\"id\":1.0,\"method\":\"ping\"}",
            "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":1.0,\"jsonrpc\":\"2.0\"}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{}}",
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-source-before-allocation",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "source_current_before_allocation",
            "callback_returns_normally": true,
            "wait_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "response_utf8": null,
        "publication_calls": 0,
        "later_callbacks": 0,
        "health_or_provider_echo": false,
        "callbacks_after_close": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-source-before-publication",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "source_current_before_publication",
            "callback_returns_normally": true,
            "wait_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "response_utf8": null,
        "publication_calls": 0,
        "later_callbacks": 0,
        "health_or_provider_echo": false,
        "callbacks_after_close": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-source-assert-current",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_to_owned_output_without_encode": true
          },
          {
            "close_original_scope": "source_current_assert_current",
            "callback_returns_normally": true,
            "wait_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "response_utf8": null,
        "publication_calls": 0,
        "later_callbacks": 0,
        "health_or_provider_echo": false,
        "callbacks_after_close": 0,
        "handle_response_before_assertion": "owned_unpublished_output",
        "assert_current_result": "owned_handoff_closed",
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-grant-before-publication",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "grant_current_before_publication",
            "callback_returns_normally": true,
            "wait_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "response_utf8": null,
        "publication_calls": 0,
        "later_callbacks": 0,
        "health_or_provider_echo": false,
        "callbacks_after_close": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-grant-assert-current",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "handle_to_owned_output_without_encode": true
          },
          {
            "close_original_scope": "grant_current_assert_current",
            "callback_returns_normally": true,
            "wait_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "private_failure",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "response_utf8": null,
        "publication_calls": 0,
        "later_callbacks": 0,
        "health_or_provider_echo": false,
        "callbacks_after_close": 0,
        "handle_response_before_assertion": "owned_unpublished_output",
        "assert_current_result": "owned_handoff_closed",
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-ping-parser",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "parser_callback",
            "callback_returns_normally": true,
            "wait_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "response_utf8": null,
        "publication_calls": 0,
        "later_callbacks": 0,
        "health_or_provider_echo": false,
        "callbacks_after_close": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "scope-close-ping-serializer",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "close_original_scope": "serializer_callback",
            "callback_returns_normally": true,
            "wait_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "owned_handoff_closed",
        "response_utf8": null,
        "publication_calls": 0,
        "later_callbacks": 0,
        "health_or_provider_echo": false,
        "callbacks_after_close": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cancel-late-completed-allocation",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "pause_acquire_before_return": true
          },
          {
            "interrupt_handle": true
          },
          {
            "finish_acquire_with_owned_resource": true
          },
          {
            "wait_release_ACK": true,
            "release_exactly_once": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "common_owned_result_utf8": "{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}"
      },
      "expected": {
        "kind": "interrupted",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": null,
        "publication_calls": 0,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "cleanup-ACK-blocks-publication",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_result_primitive": "{\"ready\":true}"
          },
          {
            "pause_release_ACK": true
          },
          {
            "assert_handle_pending": true
          },
          {
            "complete_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
        "publication_before_ACK": 0,
        "publication_after_ACK": 1,
        "health_or_provider_echo": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "initialize-negotiates-UI",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"extensions\":{\"io.modelcontextprotocol/ui\":{\"mimeTypes\":[\"text/html;profile=mcp-app\"]}}}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "source_profile": "RemoteReadOnly",
        "UI_negotiation": "source extension metadata only, no real Apps renderer/client",
        "local_metadata_port": "source initialize metadata outcome, no acquired lease"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"capabilities\":{\"extensions\":{\"io.modelcontextprotocol/ui\":{\"mimeTypes\":[\"text/html;profile=mcp-app\"]}},\"resources\":{\"listChanged\":false,\"subscribe\":false},\"tools\":{\"listChanged\":false}},\"instructions\":\"Use this remote read-only Health.md surface for readiness and typed queries only. Pairing and file-export tools are unavailable; the server operator must pair its iPhone source outside MCP. Keep Health.md foreground on the paired iPhone. Prefer healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Every query is live; there is no synchronized health-data corpus or fallback.\",\"protocolVersion\":\"2025-11-25\",\"serverInfo\":{\"name\":\"healthmd-mcp\",\"version\":\"0.1.0-alpha.7\"}}}",
        "health_or_provider_echo": false,
        "metadata_calls": 1
      }
    },
    {
      "case_id": "progress-string-128",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_emits_fixed_progress": {
              "progress": 10,
              "total": 120,
              "message": "Waiting for the paired source."
            }
          },
          {
            "dispatcher_result_primitive": "{\"ready\":true}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
        "progress_enabled": true,
        "progress_count": 1,
        "health_or_provider_echo": false,
        "progress_utf8": [
          "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"message\":\"Waiting for the paired source.\",\"progress\":10,\"progressToken\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"total\":120}}"
        ],
        "metadata_calls": 0
      }
    },
    {
      "case_id": "progress-string-129",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_emits_fixed_progress": {
              "progress": 10,
              "total": 120,
              "message": "Waiting for the paired source."
            }
          },
          {
            "dispatcher_result_primitive": "{\"ready\":true}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
        "progress_enabled": false,
        "progress_count": 0,
        "health_or_provider_echo": false,
        "progress_utf8": [],
        "metadata_calls": 0
      }
    },
    {
      "case_id": "progress-float-invalid",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":1.0}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_emits_fixed_progress": {
              "progress": 10,
              "total": 120,
              "message": "Waiting for the paired source."
            }
          },
          {
            "dispatcher_result_primitive": "{\"ready\":true}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
        "progress_enabled": false,
        "progress_count": 0,
        "health_or_provider_echo": false,
        "progress_utf8": [],
        "metadata_calls": 0
      }
    },
    {
      "case_id": "progress-i64-valid",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":9223372036854775807}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_emits_fixed_progress": {
              "progress": 10,
              "total": 120,
              "message": "Waiting for the paired source."
            }
          },
          {
            "dispatcher_result_primitive": "{\"ready\":true}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
        "progress_enabled": true,
        "progress_count": 1,
        "health_or_provider_echo": false,
        "progress_utf8": [
          "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"message\":\"Waiting for the paired source.\",\"progress\":10,\"progressToken\":9223372036854775807,\"total\":120}}"
        ],
        "metadata_calls": 0
      }
    },
    {
      "case_id": "progress-encoded-NUL-valid",
      "basis": "Independently source-derived jsonrpc.rs + locked serde_json; private lifetime supplements explicitly private",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\"}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatcher_emits_fixed_progress": {
              "progress": 10,
              "total": 120,
              "message": "Waiting for the paired source."
            }
          },
          {
            "dispatcher_result_primitive": "{\"ready\":true}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
        "progress_enabled": true,
        "progress_count": 1,
        "health_or_provider_echo": false,
        "progress_utf8": [
          "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"message\":\"Waiting for the paired source.\",\"progress\":10,\"progressToken\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\",\"total\":120}}"
        ],
        "metadata_calls": 0
      }
    },
    {
      "case_id": "expired-issuer-no-issuance",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "save_inspection_issuer": true
          },
          {
            "invoke_saved_issuer_after_callback_returns": true,
            "primitive_wire": "{}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "expired_port_outcome_disposition": "No issuance after callback; any attempted returned expired codec outcome is private_rpc_codec, never source_parse_error."
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "reentrant-codec-handle-busy",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "codec_callback_reenters_same_session_handle": true,
            "frame": "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_busy",
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "private-offset-token-1.0000000000000001",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "inspection_wire_offset_raw_token": "1.0000000000000001",
            "replace_field": "params.start",
            "all_other_wire_fields": "valid source-derived inert metadata"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "private-offset-token-1e-9999",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "inspection_wire_offset_raw_token": "1e-9999",
            "replace_field": "params.start",
            "all_other_wire_fields": "valid source-derived inert metadata"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "private-offset-token-1e9999",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "inspection_wire_offset_raw_token": "1e9999",
            "replace_field": "params.start",
            "all_other_wire_fields": "valid source-derived inert metadata"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "private-offset-token-1.0",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "inspection_wire_offset_raw_token": "1.0",
            "replace_field": "params.start",
            "all_other_wire_fields": "valid source-derived inert metadata"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "private-offset-token-1e0",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "inspection_wire_offset_raw_token": "1e0",
            "replace_field": "params.start",
            "all_other_wire_fields": "valid source-derived inert metadata"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "private-offset-token--0",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "inspection_wire_offset_raw_token": "-0",
            "replace_field": "params.start",
            "all_other_wire_fields": "valid source-derived inert metadata"
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "private_failure",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": "private_rpc_codec",
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "progress-backpressure-cancel-ACK",
      "basis": "Private owned primitive wire/lifetime policy, source public grammar unchanged",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [
          {
            "dispatch_emit_count": 17,
            "fixed_progress": {
              "progress": 10,
              "total": 120,
              "message": "Waiting for the paired source."
            }
          },
          {
            "progress_sink": "pending_forever_until_interrupt",
            "queue_capacity": 16
          },
          {
            "interrupt_owned_handle": true
          },
          {
            "wait_release_ACK": true
          }
        ],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "interrupted",
        "response_utf8": null,
        "response_LF": false,
        "dispatch_calls": 1,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "publication_calls": 0,
        "progress_pending_at_interrupt": true,
        "queue_exceeded": false,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "object-ID-UTF8-key-order",
      "basis": "Retained JSONRPC source decision order and locked serde_json Unicode/key/canonical policy; independent literal",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":{\"\ud83d\ude00\":1,\"\ue000\":0},\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":{\"\ue000\":0,\"\ud83d\ude00\":1},\"jsonrpc\":\"2.0\"}",
        "metadata_calls": 0
      }
    },
    {
      "case_id": "ID-astral-31",
      "basis": "Retained JSONRPC source decision order and locked serde_json Unicode/key/canonical policy; independent literal",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "response_utf8": "{\"id\":\"\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "raw_id_UTF8_bytes": 124,
        "encoded_id_UTF8_bytes": 126,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "ID-astral-32",
      "basis": "Retained JSONRPC source decision order and locked serde_json Unicode/key/canonical policy; independent literal",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "response_utf8": "{\"error\":{\"code\":-32600,\"message\":\"Invalid request\"},\"id\":\"\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\",\"jsonrpc\":\"2.0\"}",
        "raw_id_UTF8_bytes": 128,
        "encoded_id_UTF8_bytes": 130,
        "metadata_calls": 0
      }
    },
    {
      "case_id": "escaped-control-ID-canonical",
      "basis": "Retained JSONRPC source decision order and locked serde_json Unicode/key/canonical policy; independent literal",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":\"\\b\\f\\n\\r\\t\\u0001\\\"\\\\/\",\"method\":\"ping\"}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "health_or_provider_echo": false,
        "response_utf8": "{\"id\":\"\\b\\f\\n\\r\\t\\u0001\\\"\\\\/\",\"jsonrpc\":\"2.0\",\"result\":{}}",
        "metadata_calls": 0
      }
    },
    {
      "case_id": "source-number-overflow-id",
      "basis": "serde_json1.0.151 finite F64 parse failure; jsonrpc.rs entire Value parse before root/version/id validation",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1e9999,\"method\":\"ping\"}",
        "trusted_parser_outcome": "own_source_parse_error",
        "factory_services": "captured trusted fake ports, no real I/O"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "metadata_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null
      }
    },
    {
      "case_id": "source-number-overflow-unused-outer",
      "basis": "serde_json1.0.151 finite F64 parse failure; jsonrpc.rs entire Value parse before root/version/id validation",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"ignored\":1e9999}",
        "trusted_parser_outcome": "own_source_parse_error",
        "factory_services": "captured trusted fake ports, no real I/O"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "metadata_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null
      }
    },
    {
      "case_id": "source-number-overflow-params",
      "basis": "serde_json1.0.151 finite F64 parse failure; jsonrpc.rs entire Value parse before root/version/id validation",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"unused\":1e9999}}",
        "trusted_parser_outcome": "own_source_parse_error",
        "factory_services": "captured trusted fake ports, no real I/O"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "metadata_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null
      }
    },
    {
      "case_id": "source-number-overflow-before-version-validation",
      "basis": "serde_json1.0.151 finite F64 parse failure; jsonrpc.rs entire Value parse before root/version/id validation",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"1.0\",\"id\":1e9999,\"method\":\"ping\"}",
        "trusted_parser_outcome": "own_source_parse_error",
        "factory_services": "captured trusted fake ports, no real I/O"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 0,
        "metadata_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null
      }
    },
    {
      "case_id": "operation-success-error-shaped-json",
      "basis": "jsonrpc.rs Ok(result) => response_success; private issuance identity determines success independent of result keys",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "operation_issuer": "json",
        "common_owned_result_wire": "{\"kind\":\"object\",\"entries\":[[\"error\",{\"kind\":\"object\",\"entries\":[[\"code\",{\"kind\":\"signed_integer\",\"decimal\":\"-32602\"}],[\"message\",\"Unknown tool\"]]}]]}"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"error\":{\"code\":-32602,\"message\":\"Unknown tool\"}}}",
        "response_LF": false,
        "dispatch_calls": 1,
        "metadata_calls": 0,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null
      }
    },
    {
      "case_id": "operation-fixed-error-issuance-tag",
      "basis": "jsonrpc.rs Err(ApplicationError) => response_error; private issued error outcome carries fixed code/message",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
        "operation_issuer": "error",
        "code": -32602,
        "fixed_message": "Unknown tool"
      },
      "expected": {
        "kind": "response",
        "response_utf8": "{\"error\":{\"code\":-32602,\"message\":\"Unknown tool\"},\"id\":1,\"jsonrpc\":\"2.0\"}",
        "response_LF": false,
        "dispatch_calls": 1,
        "metadata_calls": 0,
        "allocation_calls": 1,
        "release_ACKs": 1,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null
      }
    },
    {
      "case_id": "initialize-plain-HTML-does-not-negotiate-UI",
      "basis": "Root independent retained-source literal: apps.rs MIME_TYPE exact match required by jsonrpc.rs initialize; plain HTML extension does not enable UI.",
      "stimulus": {
        "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"extensions\":{\"io.modelcontextprotocol/ui\":{\"mimeTypes\":[\"text/html\"]}}}}}",
        "trusted_parser": "source-semantic inert descriptor",
        "dispatcher": "no_data_fake",
        "actions": [],
        "factory_services": "captured_trusted_fake_ports_no_real_IO",
        "source_profile": "RemoteReadOnly",
        "UI_negotiation": "Exact source MIME mismatch remains valid initialize with tools capability only",
        "local_metadata_port": "source initialize metadata outcome, no acquired lease"
      },
      "expected": {
        "kind": "response",
        "response_LF": false,
        "dispatch_calls": 0,
        "allocation_calls": 0,
        "release_ACKs": 0,
        "source_calls": 0,
        "forbidden_IO_calls": 0,
        "proxy_traps": 0,
        "private_failure": null,
        "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"capabilities\":{\"tools\":{\"listChanged\":false}},\"instructions\":\"Use this remote read-only Health.md surface for readiness and typed queries only. Pairing and file-export tools are unavailable; the server operator must pair its iPhone source outside MCP. Keep Health.md foreground on the paired iPhone. Prefer healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Every query is live; there is no synchronized health-data corpus or fallback.\",\"protocolVersion\":\"2025-11-25\",\"serverInfo\":{\"name\":\"healthmd-mcp\",\"version\":\"0.1.0-alpha.7\"}}}",
        "health_or_provider_echo": false,
        "metadata_calls": 1
      }
    }
  ],
  "exact_number_source_cases": [
    {
      "representation": "signed_integer",
      "payload": "9223372036854775807",
      "expected_UTF8": "9223372036854775807"
    },
    {
      "representation": "unsigned_integer",
      "payload": "9223372036854775808",
      "expected_UTF8": "9223372036854775808"
    },
    {
      "representation": "binary64",
      "payload": "8000000000000000",
      "expected_UTF8": "-0.0"
    },
    {
      "representation": "binary64",
      "payload": "3ff0000000000000",
      "expected_UTF8": "1.0"
    },
    {
      "representation": "binary64",
      "payload": "3ff8000000000000",
      "expected_UTF8": "1.5"
    }
  ],
  "numeric_reuse_source": {
    "path": "packages/healthmd-core-ts/src/serialization/exact-json-numbers.ts",
    "bytes": 5809,
    "sha256": "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52"
  },
  "numeric_reuse_export": null,
  "source_dependency_pins": [
    {
      "path": "/Users/codybontecou/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/serde_json-1.0.151/src/de.rs",
      "bytes": 86840,
      "sha256": "4998d7e252eb513be85b298e287048b4fb283882e9ba7df905f572f07200f3f3"
    },
    {
      "path": "/Users/codybontecou/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/serde_json-1.0.151/src/number.rs",
      "bytes": 25285,
      "sha256": "70b83c36286f6c58123f544f27db2b54a1135f928fe33b08b521b2997773f862"
    },
    {
      "path": "/Users/codybontecou/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/serde_json-1.0.151/src/map.rs",
      "bytes": 35057,
      "sha256": "b5a2fd1ee865e6cfd83ef2da0a2e1057f892465ac7ede8a78a11354a60526f33"
    },
    {
      "path": "/Users/codybontecou/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/serde_json-1.0.151/src/value/de.rs",
      "bytes": 41251,
      "sha256": "ceda1bf415aafde89caa83bf275811b70d393717d4e1038e0c61822d2da02993"
    },
    {
      "path": "/Users/codybontecou/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/serde_json-1.0.151/src/ser.rs",
      "bytes": 63877,
      "sha256": "f2b8cc0b97e30c49dbc58698fa22c14a7d56ea616cdb57b067835a59af49a75f"
    },
    {
      "path": "/Users/codybontecou/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/zmij-1.0.21/src/lib.rs",
      "bytes": 47412,
      "sha256": "d843c3c1c8a41a8cdaead2ee3a223a204bf2ed047c3f2892719248a0f10d9bef"
    }
  ],
  "numeric_reuse_admission": {
    "source_implementation": "packages/healthmd-core-ts/src/serialization/exact-json-numbers.ts",
    "current_package_export": false,
    "root_index_export": false,
    "proposed_action": "Do not duplicate renderer or add exports. Full codec adapter owner must separately admit existing pure scalar implementation through an allowed existing/explicitly reviewed interface before real serializer implementation. This child injects trusted serializer; fakes supply independently frozen primitive canonical bytes.",
    "unqualified": "No guessed @healthmd/core-ts/candidate/exact-json-numbers import."
  },
  "fixture_stimulus_semantics": {
    "case_ID": "Only harness label; never passed into candidate, authority, dispatch or serializer. Port fake stimuli use explicit frame/primitive result/actions.",
    "expected_bytes": "Frozen literals independently sourced from Rust/locked serde, never candidate-produced. Source codec fake receives explicit semantic metadata supplied by harness as a separate source-derived adapter fixture; no full parser equivalence claim.",
    "budgets": "Count root and each JSON value as nodes; object keys are not values; root depth1, nested array value increases depth1; raw UTF8 computed without replacement and reject illformed UTF16 before codec. Structural scanning preserves numeric lexemes and decoded duplicate keys.",
    "scope_actions": "Actual Scope.close on captured original Scope inside indicated callback; callback may return normally. Allocation resource counter increments upon completion, release callback exactly once and explicit Deferred ACK. New Scope/provided Layer cannot revive.",
    "progress": "Actual pending bounded queue/sink effects; fake emission payload fixed health-free source progress, no method/case lookup of expectedbytes."
  },
  "additional_assigned_source_pins": [
    {
      "path": "packages/healthmd-core-ts/package.json",
      "bytes": 1410,
      "sha256": "822034747afb2524a9133adc8869b453bac601a981141144f71a3ce5f24462f2",
      "matches_assigned_Git": true
    },
    {
      "path": "packages/healthmd-core-ts/src/index.ts",
      "bytes": 319,
      "sha256": "3b2632b7f93517e259be66242444b449402d0a3821c38a76b6b28c6abce256d8",
      "matches_assigned_Git": true
    },
    {
      "path": "packages/healthmd-core-ts/src/serialization/exact-json-numbers.ts",
      "bytes": 5809,
      "sha256": "519d954f432d5ce4ecfc55bd3c0fa03232e84837e55900c1982a839ae0a48a52",
      "matches_assigned_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/apps.rs",
      "bytes": 3022,
      "sha256": "77a7fb5f16c78b0f1fdac4bdcc0569180e5926fe966499874152c01349d45336",
      "matches_assigned_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/catalog.rs",
      "bytes": 1729,
      "sha256": "74fcf993add2dfb5cfab608ac9c25b46b2e92e8d68f3d04a5f604738039194b9",
      "matches_assigned_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/transport/streamable_http.rs",
      "bytes": 44066,
      "sha256": "645624818ab535982df3af4a85908caeab0ee95a46ee5cb0b4964afeee25dccf",
      "matches_assigned_Git": true
    },
    {
      "path": "apps/cli/Cargo.lock",
      "bytes": 88843,
      "sha256": "2ceea3ac125f41d6d89230af204dc619152a0b657cbcefe6d1ce817fbc213bd5",
      "matches_assigned_Git": true
    },
    {
      "path": "apps/cli/Cargo.toml",
      "bytes": 2646,
      "sha256": "55c7b45a78c3c87918d93fce970196f50468e616e85583f8eeb283f14bc3d90d",
      "matches_assigned_Git": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/OP-CATALOG.json",
      "bytes": 17512,
      "sha256": "a3ce7294241c2bd32051d0a296977e73eda01197b40a04666dee35edb9e6f758",
      "matches_assigned_Git": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CORE-COHORT-IOS-ELIGIBILITY.json",
      "bytes": 171341,
      "sha256": "2aeb43dc54043fef42e8f2ace7ddafb46c915d54b659034e2b1fc74143f207c0",
      "matches_assigned_Git": true
    },
    {
      "path": "docs/migration/effect-refactor/cohorts/core-ts-ios-eligibility-v1.json",
      "bytes": 47904,
      "sha256": "25b48beb5c7cd641d3161b3b362accdabf04bc0a5118042209651e88e18fe761",
      "matches_assigned_Git": true
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CLI-DISCOVERY-NORMALIZER.json",
      "bytes": 178234,
      "sha256": "136e18c58fb939d8157784f3bfff6de5f2da869bfa19589baeac2ac8ac8adce2",
      "matches_assigned_Git": true
    }
  ],
  "source_symbol_locators": [
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 11,
      "symbol": "MAXIMUM_REQUEST_ID_BYTES",
      "line_sha256": "2e04ce67e07aa7bfa0b29610d607299ef83ec2ba5d3f91c3b42d05a3b4c393c4",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 12,
      "symbol": "MAXIMUM_USED_REQUEST_IDS",
      "line_sha256": "d5d479a72ecc539361c8569d54c4a0e9e7783e673db58a9731a2a468cedb626b",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 13,
      "symbol": "const PROTOCOLS",
      "line_sha256": "cf8c425ccf5a1327cb877dd6101bb1289e030386f46a749ae8ca6461fb906549",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 60,
      "symbol": "async fn handle_with_caller(",
      "line_sha256": "0fcd942843f0b908a8cbc9050629d094b35409794a8cc13b0a8a6ac9683f35ab",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 199,
      "symbol": "fn initialize(",
      "line_sha256": "624e8ba6b3943d1e218182bc849d9ff68cc3436b185044937a346eb0e1e680b8",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 263,
      "symbol": "fn request_id_key(",
      "line_sha256": "8c72dc4fbe0113b2dbe796e0f6114568ba32f7f055542fbc6adc3116ce7c77e4",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 280,
      "symbol": "fn response_success(",
      "line_sha256": "ad9ae4ffc606c810d01467000bdb983edc0a8938765154a9c4d2e472275fb0bc",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 286,
      "symbol": "fn response_error(",
      "line_sha256": "09b319a449ec38a7bad045679dedb7c78ef90ca9a63923c3fa05dcc2fea9801c",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/result.rs",
      "line": 66,
      "symbol": "fn tool_result(",
      "line_sha256": "06cdbfd62b664e1cd1fdd429aa6e76a8f444f64080389284640bf72690558964",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/result.rs",
      "line": 15,
      "symbol": "fn query_tool_result(",
      "line_sha256": "2fce152496c2b5688355d0caa5b3211bbd00348d96db71e411f327740412ce4f",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/result.rs",
      "line": 39,
      "symbol": "fn pairing_start_tool_result(",
      "line_sha256": "c8d66a0253cbd9d1cc35171514ce1a926a6f0491ef46b8e43ab0dbf340e91bae",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "matches_current_and_historical_Git": true
    }
  ],
  "source_test_locators": [
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 356,
      "case_id": "initializes_and_returns_the_shared_catalog",
      "line_sha256": "16fb24984ae3adc24d231929fd856fcde4f2beb5ce85d91422f68db2295d1c84",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "executed_during_planning": false,
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 388,
      "case_id": "forwards_bounded_mcp_progress_notifications",
      "line_sha256": "0e837594aad65d46f13e885bc7022f2d20735741337116ab6839f93360cdbdf9",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "executed_during_planning": false,
      "matches_current_and_historical_Git": true
    },
    {
      "path": "apps/cli/crates/healthmd-mcp/src/jsonrpc.rs",
      "line": 424,
      "case_id": "request_identifiers_are_scalar_bounded_and_never_reused",
      "line_sha256": "bf2267c1bed7a487fafe69e83e654399c8a8aedd41ac3499fe4cda319c174ead",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "executed_during_planning": false,
      "matches_current_and_historical_Git": true
    }
  ],
  "accepted_inventory_pointer_pins": [
    {
      "reference": "docs/migration/effect-refactor/inventories/cli.json#/mcp_envelope",
      "canonical_value_sha256": "6734acad95563335397a4c04a1373a5d0b2a9ba9c1da27a0a4975a7a20658505"
    },
    {
      "reference": "docs/migration/effect-refactor/inventories/cli.json#/catalog",
      "canonical_value_sha256": "b6a892cde559911724c44036b7776759cb60efe1887a2e21be7307c3d18fc067"
    },
    {
      "reference": "docs/migration/effect-refactor/inventories/cli.json#/schemas",
      "canonical_value_sha256": "7727d22b9038b43470834b44cc107b7d5b4a7d46255e90749c5056930b84a9d2"
    }
  ],
  "case_count": 143,
  "source_ownership": {
    "Health_ordinary_CLI_commands": 14,
    "feature_HTTP_separate": true,
    "Health_full_MCP_operations": 21,
    "Health_readonly_MCP_operations": 13,
    "donor_time_md_tools": 40,
    "donor_authority_separate": true,
    "common_behavior_owner": "accepted common operations; fake metadata/results in this child are not a second evaluator",
    "catalog_and_schema_source": "Pinned mcp-tools-v1/application/catalog/registry; actual fixed catalog/schema parity deferred with concrete owner/trigger."
  },
  "independent_stage1_revision_authority": {
    "path": "/private/tmp/healthmd-mcp-envelope-root-stage1-review.json",
    "raw_sha256": "fcca84aed6b783110c904c8c28b326c364a41e6c7bc34a422d9b35e5e553ab07",
    "reviewer": "/root",
    "literal_proposal_count": 6,
    "proposal_policy": "Six exact root proposal subtrees adopted without regenerated expected bytes; old136vector/rawreceipt preserved under private/tmp. Only metadata counter/interface corrections authorized before code."
  }
} as const;
