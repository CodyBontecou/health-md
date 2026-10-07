// Stage1 independent literal/interface proposal only; no eligibility implementation or test executed.
import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
export type IOSUsageEligibilityFailureCode = "unsupported_request" | "source_profile_unadmitted" | "candidate_limit_exceeded" | "invalid_host_binding" | "scope_not_authorized" | "unavailable" | "scope_binding_mismatch" | "owned_handoff_closed" | "cleanup_unacknowledged";
export interface IOSUsageEligibilityFailure { readonly _tag: "IOSUsageEligibilityFailure"; readonly code: IOSUsageEligibilityFailureCode }
export type IOSUsageEligibilityPhase = "before_allocation" | "before_publication" | "assert_current";
export interface IOSUsageEligibilityRequest { readonly profile: "synthetic.ios.usage.eligibility.v1"; readonly source_id: string; readonly source_revision: string; readonly installation_id: string; readonly purpose: "local_usage" | "local_display"; readonly requested: "data_read" | "report_display"; readonly destination: "local_report" | "local_query" | "local_file" | "paired_device" | "external_agent"; readonly job_id: string; readonly selection_id: string; readonly detail: "app_duration" | "app_label"; readonly page_limit: number; readonly record_limit: number }
export interface IOSUsageEligibilityBinding extends IOSUsageEligibilityRequest { readonly authorization_state: "approved" | "approvedWithDataAccess" | "denied" | "notDetermined" | "unavailable"; readonly route: "display_only" | "aggregate_read_handoff" | "unavailable"; readonly admission: "synthetic_qualified" | "unproven"; readonly proof_ref: string; readonly frontier_lineage: string; readonly frontier_revision: string }
export interface IOSUsageEligibilityResource { readonly release: Effect.Effect<void, IOSUsageEligibilityFailure> }
export interface IOSUsageEligibilityCatalogService { readonly resolve: (request: IOSUsageEligibilityRequest) => Effect.Effect<string, IOSUsageEligibilityFailure>; readonly checkSource: (binding: IOSUsageEligibilityBinding, phase: IOSUsageEligibilityPhase) => "permitted" | "scope_not_authorized" | "unavailable" | "scope_binding_mismatch"; readonly allocate: (binding: IOSUsageEligibilityBinding) => Effect.Effect<IOSUsageEligibilityResource, IOSUsageEligibilityFailure> }
export interface IOSUsageCurrentAuthorityService { readonly current: (binding: IOSUsageEligibilityBinding, phase: IOSUsageEligibilityPhase) => string }
export interface OwnedIOSUsageHandoff { readonly _tag: "OwnedIOSUsageHandoff"; readonly kind: "display_only" | "aggregate_read_handoff"; readonly native_qualification: false; readonly export_allowed: false; readonly assertCurrent: (input: unknown) => Effect.Effect<void, IOSUsageEligibilityFailure> }
// Service marker types are planning interface only; runtime Context.Service tags belong to the later source.
export interface IOSUsageEligibilityCatalog { readonly _IOSUsageEligibilityCatalog: unique symbol }
export interface IOSUsageCurrentAuthority { readonly _IOSUsageCurrentAuthority: unique symbol }
export interface IOSUsageEligibilityGate { readonly open: (input: unknown) => Effect.Effect<OwnedIOSUsageHandoff, IOSUsageEligibilityFailure, IOSUsageEligibilityCatalog | IOSUsageCurrentAuthority | Scope.Scope> }

export const iosUsageEligibilityInterfaceProposal = "Private revision1 gate-only proposal. createIOSUsageEligibilityGate() creates one factory-local ownership slot and open(input: unknown): Effect<OwnedIOSUsageHandoff, IOSUsageEligibilityFailure, IOSUsageEligibilityCatalog | IOSUsageCurrentAuthority | Scope>. Future source implementation supplies two Context.Service tags healthmd.candidate.IOSUsageEligibilityCatalog and healthmd.candidate.IOSUsageCurrentAuthority; tests provide fake Layers. Untrusted input is accepted ONLY if typeof input is string before any property, prototype, iterator, valueOf, toString, Symbol, Proxy or accessor operation. No coercion. Strict scalar UTF8 counting checks input code-unit length first, rejects unpaired surrogates and NUL, and aborts at4096 UTF8 bytes before allocating/parse. Bounded linear JSON scanner rejects depth>4,nodes>64, duplicate including escaped-equivalent keys, incomplete escapes/trailing data and noncanonical number lexemes before JSON map creation. Flat closed request exactly the12 fields in request_example; all opaque identity/profile strings scalar Unicode, nonempty and <=128 UTF8 bytes; profile exactly synthetic.ios.usage.eligibility.v1; purpose local_usage or local_display; requested data_read or report_display; destination local_report/local_query/local_file/paired_device/external_agent; detail app_duration or app_label only; page_limit canonical integer1..32; record_limit canonical integer1..4096. Strings preserve case/order/scalars without normalization. No caller authorization/entitlement/current frontier/account/title/payload fields. Unsupported object/schema yields unsupported_request; valid unknown profile yields source_profile_unadmitted; bounds yield candidate_limit_exceeded. All preauthority failures have zero host calls/allocations/traps. Unicode bounds are private unmeasured guards, not physical SDK budgets. Request page/record limits are future handoff intent only; gate performs no page traversal, record decode, reconciliation, reduction or reading. Exactly one pending/open handoff per factory; reserve the slot atomically before preparatory catalog work, deny competing open with candidate_limit_exceeded before host work, release unused reservation on failure/interruption. Do not use a global/shared native lock.\nCatalog.resolve(frozenRequest): Effect<primitive binding JSON, fixed failure> is interruptible source metadata preparation, NEVER personal observation. Its independent trusted installed-source/purpose/channel eligibility proof includes signed channel/API/purpose/account/region/one-app state when a real host is qualified; a request flag cannot stand in. Synthetic Layers explicitly simulate those decisions, qualify no real iOS16/iOS26.4, entitlement or agreement. Binding JSON strict bounded flat primitive4096/depth4/nodes64 grammar exactly request fields plus authorization_state,route,admission,proof_ref,frontier_lineage,frontier_revision. All request fields match exactly except route expresses report fallback; no crosswire source/install/revision/purpose/request/destination/job/selection/detail/bounds. authorization_state approved/approvedWithDataAccess/denied/notDetermined/unavailable; admission synthetic_qualified/unproven; route display_only/aggregate_read_handoff/unavailable. proof_ref and frontier_lineage nonempty scalar<=128UTF8; frontier_revision canonicalu64 string. Catalog response duplicates/objects/extra fields/bad numeric bounds fail invalid_host_binding with no allocation. unproven or unavailable/notDetermined eligibility yields unavailable with no usage zero; denied yields scope_not_authorized. Standard approved can supply display_only ONLY with local_display/local_report and separately current display grant, including data_read request fallback; never data access/export. approvedWithDataAccess may supply synthetic aggregate_read_handoff with local_usage/data_read and separately current query/detail/destination admission. report_display requires display_only/local_display/local_report. Label detail is independent permission, not permission for browser window title. Unknown app classification never authorizes browser/title/input observation. Unsupported native source/profile remains unadmitted even if body resembles synthetic binding. Binding is metadata only and deeply frozen.\nCatalog.checkSource(binding, phase) is a synchronous current trusted source/purpose/detail/display/query/catalog/eligibility decision permitted/scope_not_authorized/unavailable/scope_binding_mismatch. It contains no payload and independently validates active installed proof. CurrentAuthority.current(binding, phase) immediately follows each successful source check, returning ONLY primitive flat bounded JSON matching current_example. It is a trusted atomic current authorization snapshot checking the entire same source/purpose/detail/display/query plus separate destination/job/grant and latest complete independently trusted external delete/revoke frontier. It is not a cached catalog assertion or self-declared journal freshness. Every returned identity/proof/frontier lineage must bind the handoff; initial frontier_revision must equal catalog binding and becomes pinned handoff revision; The INITIAL trusted permitted current snapshot pins grant_revision privately in the owned operation alongside frontier_revision; catalog binding deliberately carries no grant_revision and callers cannot supply it. grant_revision is canonicalu64 metadata from the independently trusted current authority, never caller authority. Canonicalu64 means exactly 0 or a nonzero ASCII decimal digit followed by ASCII digits, no sign/leading zero/space/fraction/exponent, numeric JSON value or boolean, range0..18446744073709551615, <=20 decimal digits; malformed/noncanonical/overflow grant or frontier revision is invalid_host_binding before allocation/publication. For each later check the decision is evaluated FIRST: explicit scope_not_authorized wins even if grant/frontier revision changed; unavailable/scope_binding_mismatch decisions stay their fixed failures. Only permitted then compares all binding identities plus both pinned revision values. Any grant_revision OR frontier_revision change after the initial check returns scope_binding_mismatch before publication or on assertCurrent, including revoke/regrant that restores permission with a higher grant revision. No repinning or refresh-in-place; a separately opened fresh handoff requires complete current authority and cannot override suppression of old lineage. decision permitted/scope_not_authorized/unavailable/scope_binding_mismatch; only permitted proceeds. Missing/stale/incomplete/wrong-lineage external authority or suppressed old evidence cannot proceed. Later permitted snapshot revision change of EITHER grant_revision or frontier_revision returns scope_binding_mismatch; delete/revoke decision dominates regrant/local Undo/old backup/rekey and yields scope_not_authorized. Callback reentry that revokes destination/job/source/frontier in checkSource must be observed by the following current snapshot BEFORE allocation or handoff publication. A hostile arbitrary trusted adapter violating atomic-snapshot/source policy is not authenticated by this synthetic interface. After any await/allocate repeat checkSource then current. No callback between the final current decision and synchronous immutable handoff publication.\nCatalog.allocate(binding): Effect<IOSUsageEligibilityResource, fixed failure> creates exactly one synthetic aggregate-read-capability OR display-only-report handle; no permission prompt, view mount, activity/React host, report bytes, native queries, URLs/domains/history/titles/input APIs, storage or export. Preparation stays in resolve. Completed allocation and release-finalizer registration are atomic and uninterruptible in Scope; trusted allocate is bounded and cleans partial/failed allocations itself. Source adapter owns its private resource, returned token never crosses output. The owned resource.release: Effect<void,fixed failure> is awaited uninterruptibly exactly once on Scope exit including cancellation and typed failure. Exposed handoff has only _tag, kind, native_qualification:false, export_allowed:false, and assertCurrent(input: unknown): Effect<void, IOSUsageEligibilityFailure>; no native token, authority booleans, payload, read/page/report/export/delivery methods, provenance identifiers or provider error fields. The gate never hashes/logs/retains personal payload. handoff belongs only to its original factory/Scope, with private closure identity and live flag. assertCurrent accepts the same closed primitive request grammar and compares every field to the frozen original (JSON member order irrelevant, strings exact); crosswire fails scope_binding_mismatch before host calls. It then checks Scope is live and current source followed by atomic authority snapshot. open resolves/captures the original trusted catalog and current-authority service instances exactly once in its Effect environment; the returned assertCurrent effect requires NO environment and closes over those same captured trusted instances, original Scope live token, frozen request/binding and privately pinned revisions. Reproviding another Layer/environment to assertCurrent cannot switch source/authority, change ownership or bypass revision/liveness checks. Scope close/cleanup-start permanently invalidates that token before release; an escaped handoff never resurrects even under reprovided services, a new Scope, a newly opened same-request handoff, or later regrant. No native handle or resource leaks through captured services. Authoritative callbacks remain current calls into the same service, never cached approval snapshots. After close/cleanup starts, assertCurrent fails owned_handoff_closed before host callbacks; an escaped object cannot reactivate its capability. Factory capacity is freed only after acknowledged release; failed release poisons the factory with cleanup_unacknowledged and future open cannot bypass uncertain cleanup. Closed handoff never exposes the resource. Cancellation after allocation before publication produces zero handoffs and waits release ACK. Cancellation after publication prevents later assertCurrent while Scope closes; no recall of already copied metadata is promised.\nFailures exactly {_tag:IOSUsageEligibilityFailure,code} with code unsupported_request/source_profile_unadmitted/candidate_limit_exceeded/invalid_host_binding/scope_not_authorized/unavailable/scope_binding_mismatch/owned_handoff_closed/cleanup_unacknowledged. Provider typed errors/throws/defects become fixed unavailable; cleanup error becomes fixed cleanup_unacknowledged. Interrupt-only causes preserve interruption but remove provider identity/reason/annotations using fresh interrupt; mixed cleanup defect retains only fresh interrupt plus fixed cleanup_unacknowledged, never falsely ACK. Completion is observed by Effect.scoped(open/use) after finalizer, not by open's temporary handoff alone. No cleanup fault reports success. All handoffs have native_qualification:false/export_allowed:false and zero personal reads/materializations/deliveries/web/title/input observations/persistent private state writes. Those zero-write counters refer candidate-owned personal/private data, not runtime/compiler caches/harness reports. Literal five packet proposals retained separately exactly; full gate stimuli below elaborate them before implementation. All81 immutable Personal obligations and four original records are retained unchanged but no payload/precision/history/native/page implementation qualification follows from gate-only tests. Local account-free use remains separate from optional cloud/account entitlement; iOS bucket data never exact app sessions, iOS S06/native reports/production admission/history/query/reducer/archive/UI/export/cloud remain separately assigned. No source/profile/native/public/package/index/lock/cohort admission or donor adoption." as const;

export const iosUsageEligibilityGrammar = {
  "request_example": {
    "profile": "synthetic.ios.usage.eligibility.v1",
    "source_id": "synthetic-ios-source-a",
    "source_revision": "synthetic-contract1",
    "installation_id": "synthetic-install-a",
    "purpose": "local_usage",
    "requested": "data_read",
    "destination": "local_query",
    "job_id": "synthetic-job-a",
    "selection_id": "synthetic-selection-a",
    "detail": "app_duration",
    "page_limit": 32,
    "record_limit": 4096
  },
  "binding_example": {
    "profile": "synthetic.ios.usage.eligibility.v1",
    "source_id": "synthetic-ios-source-a",
    "source_revision": "synthetic-contract1",
    "installation_id": "synthetic-install-a",
    "purpose": "local_usage",
    "requested": "data_read",
    "destination": "local_query",
    "job_id": "synthetic-job-a",
    "selection_id": "synthetic-selection-a",
    "detail": "app_duration",
    "page_limit": 32,
    "record_limit": 4096,
    "authorization_state": "approvedWithDataAccess",
    "route": "aggregate_read_handoff",
    "admission": "synthetic_qualified",
    "proof_ref": "synthetic-installed-channel-proof-a",
    "frontier_lineage": "synthetic-suppression-a",
    "frontier_revision": "7"
  },
  "current_example": {
    "decision": "permitted",
    "source_id": "synthetic-ios-source-a",
    "source_revision": "synthetic-contract1",
    "installation_id": "synthetic-install-a",
    "purpose": "local_usage",
    "destination": "local_query",
    "job_id": "synthetic-job-a",
    "selection_id": "synthetic-selection-a",
    "detail": "app_duration",
    "proof_ref": "synthetic-installed-channel-proof-a",
    "frontier_lineage": "synthetic-suppression-a",
    "frontier_revision": "7",
    "grant_revision": "3"
  },
  "request_raw_utf8_limit": 4096,
  "request_depth_limit": 4,
  "request_nodes_limit": 64,
  "identifier_utf8_limit": 128,
  "maximum_pending_handoffs": 1,
  "page_limit": 32,
  "record_limit": 4096,
  "payload_reads_in_this_task": 0,
  "budget_status": "unmeasured private proposals; no SDK budget qualification"
} as const;

export const iosUsageEligibilityProvenance = {
  "assigned_source": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
  "packet": {
    "path": "docs/migration/effect-refactor/expansions/split-usage-mobile.json",
    "raw_sha256": "b4583feb5118bcb5d0ed7db36369219cc418017e5415f240614eb516a5b8c572",
    "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
    "child_pointer": "#/children/0"
  },
  "current_git_input_pins": [
    {
      "path": "AGENTS.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "563ac20e38bf5e62d636f5e3a4f15e1f8a0b4d96c67d8150de0badcf89bef456",
      "bytes": 6129
    },
    {
      "path": "GLOSSARY.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65",
      "bytes": 3868
    },
    {
      "path": "docs/architecture/javascript-unified-layer-research.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3",
      "bytes": 13361
    },
    {
      "path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd",
      "bytes": 284562
    },
    {
      "path": "docs/architecture/cross-platform-unification-policy.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "49a35d47c37bd721c9d2a83607a3a4bdc7c82a26a7ceae160f5208bd577b95fc",
      "bytes": 9482
    },
    {
      "path": "docs/migration/effect-refactor/personal-data.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "0f532bf08cbbf2e704bb39c85269874c0299dd9bfcf54ee5e21ba726dde98ea0",
      "bytes": 5582
    },
    {
      "path": "docs/migration/effect-refactor/templates.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e",
      "bytes": 10054
    },
    {
      "path": "apps/apple/AGENTS.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "043f8c654e9de3489a654f3caba9ba448f4fe1e8704dea923310fc4d10520d13",
      "bytes": 5233
    },
    {
      "path": "apps/android/AGENTS.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "cde6428339645524077ae5395b3d45a8787a9374d5568412e8dccd240f47770c",
      "bytes": 2502
    },
    {
      "path": "packages/healthmd-core-ts/AGENTS.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67",
      "bytes": 860
    },
    {
      "path": "packages/healthmd-core-ts/README.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "e8c4f43bbd82db28f995d342589c66de8a3d1f5443d173d81ee3b40df5d1e606",
      "bytes": 2988
    },
    {
      "path": "docs/migration/effect-refactor/inventories/donor-usage-mobile.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "bbfef9fe1576085ed006cb05b74ec7336adee09ffa4f4ed1a8cca309403a105d",
      "bytes": 143057
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-DONOR-USAGE-MOBILE.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "f8cec1de88b331ebff3d604802afba6b06e26a1c85c669d36dfc94a7a7e2649d",
      "bytes": 18863
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-candidate.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "0c50c6d13e48026c9ed81f0325fea73050d52d7b1aa744eb905eae4884b0349d",
      "bytes": 13492
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "856276a9a184d466ead3c7e9c6c865e782ec830562cbf31e68a3d2d3dfd9775c",
      "bytes": 68436
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "1b63355846d9a5637ee723f8199b0bf7774a601479e0092ed52ca9b8fdf606df",
      "bytes": 34193
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-DRAFT.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "2325ad12401e52963f00c622f3e81fb8210e7b6396604516595a7610cb3a8643",
      "bytes": 11380
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-REVIEW.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "9c1f44fd63b564fe9a5d0ee6eaeff2a22f34615b1abfd59d8efe23bd4154b4ae",
      "bytes": 18284
    },
    {
      "path": "docs/migration/effect-refactor/expansions/split-usage-desktop.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "8aeedc538783d9e0373adec386f0bd9f1ce7a92c8a368c3d6ab2711e7ce2097f",
      "bytes": 139864
    },
    {
      "path": "docs/migration/effect-refactor/decisions/cloud-fault-cases.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "07a75cfe6624acec4a6a3f12cb8ae6f52d9fe1dc1b67339affd2566587b2d974",
      "bytes": 78932
    },
    {
      "path": "docs/migration/effect-refactor/decisions/cloud-fault-model.md",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "02adec90b5b23bee196de9f9b6573e2a1f05537767ae36a9a39eb830b8d1492d",
      "bytes": 5423
    },
    {
      "path": "docs/migration/effect-refactor/expansions/split-usage-mobile.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "b4583feb5118bcb5d0ed7db36369219cc418017e5415f240614eb516a5b8c572",
      "bytes": 257479
    },
    {
      "path": "packages/healthmd-core-ts/src/contracts/personal-slice.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "09e0df4038e6847bf2d13f80757e20da36eae09295c6c14e1c2ee9e48651a8e5",
      "bytes": 25746
    },
    {
      "path": "packages/healthmd-core-ts/tests/personal-codecs-vectors.ts",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "274b6dc844d2da72ff283df5d194dc39002639b3a2038937db732278fda4406a",
      "bytes": 120095
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CODECS.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "c627a6ce596ea971b079917eb078a5fae02faca57894609147b03921fe6fc859",
      "bytes": 24593
    },
    {
      "path": "docs/migration/effect-refactor/cohorts/core-ts-personal-slices-v1.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "1dbee84851fb08b26a66d436014496f097fc94fafeeef880846897ca13ba4853",
      "bytes": 34945
    },
    {
      "path": "docs/migration/effect-refactor/receipts/CORE-COHORT-PERSONAL-SLICES.json",
      "source_revision": "203c82f73560ca7cc6cce5ddf69c06bf3b124735",
      "sha256": "faaa45e7d1d19a2cd4b69eec7f05d29bd332a4beacc1fcff36111259a462c602",
      "bytes": 124059
    }
  ],
  "accepted_packet21_input_pins": [
    {
      "path": "AGENTS.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 6129,
      "sha256": "563ac20e38bf5e62d636f5e3a4f15e1f8a0b4d96c67d8150de0badcf89bef456"
    },
    {
      "path": "GLOSSARY.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 3868,
      "sha256": "c128162016990d3f2dca7233808e36867ce683019828acb803acace9736d6a65"
    },
    {
      "path": "docs/architecture/javascript-unified-layer-research.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 13361,
      "sha256": "feac64a79a2a9967cabd07f4155ed1b5eaa1f05fae2aa6ea37d468eddf87bba3"
    },
    {
      "path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 284562,
      "sha256": "2c3acaf2df187e1a78516eddfb3d82958092b71894b669aabfc7c86d569039bd"
    },
    {
      "path": "docs/architecture/cross-platform-unification-policy.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 9482,
      "sha256": "49a35d47c37bd721c9d2a83607a3a4bdc7c82a26a7ceae160f5208bd577b95fc"
    },
    {
      "path": "docs/migration/effect-refactor/personal-data.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 5582,
      "sha256": "0f532bf08cbbf2e704bb39c85269874c0299dd9bfcf54ee5e21ba726dde98ea0"
    },
    {
      "path": "docs/migration/effect-refactor/templates.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 10054,
      "sha256": "53c198716d79bae941c55caa634712c9fdc60a451da6f8c58847a110a8ec077e"
    },
    {
      "path": "apps/apple/AGENTS.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 5233,
      "sha256": "043f8c654e9de3489a654f3caba9ba448f4fe1e8704dea923310fc4d10520d13"
    },
    {
      "path": "apps/android/AGENTS.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 2502,
      "sha256": "cde6428339645524077ae5395b3d45a8787a9374d5568412e8dccd240f47770c"
    },
    {
      "path": "packages/healthmd-core-ts/AGENTS.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 860,
      "sha256": "14b3f153a9eb9d2087992b7fa90b722fc8538845f1e33c0dfdf55de32c3fca67"
    },
    {
      "path": "packages/healthmd-core-ts/README.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 2988,
      "sha256": "e8c4f43bbd82db28f995d342589c66de8a3d1f5443d173d81ee3b40df5d1e606"
    },
    {
      "path": "docs/migration/effect-refactor/inventories/donor-usage-mobile.json",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 143057,
      "sha256": "bbfef9fe1576085ed006cb05b74ec7336adee09ffa4f4ed1a8cca309403a105d"
    },
    {
      "path": "docs/migration/effect-refactor/receipts/BASE-DONOR-USAGE-MOBILE.json",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 18863,
      "sha256": "f8cec1de88b331ebff3d604802afba6b06e26a1c85c669d36dfc94a7a7e2649d"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-candidate.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 13492,
      "sha256": "0c50c6d13e48026c9ed81f0325fea73050d52d7b1aa744eb905eae4884b0349d"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 68436,
      "sha256": "856276a9a184d466ead3c7e9c6c865e782ec830562cbf31e68a3d2d3dfd9775c"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 34193,
      "sha256": "1b63355846d9a5637ee723f8199b0bf7774a601479e0092ed52ca9b8fdf606df"
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-DRAFT.json",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 11380,
      "sha256": "2325ad12401e52963f00c622f3e81fb8210e7b6396604516595a7610cb3a8643"
    },
    {
      "path": "docs/migration/effect-refactor/receipts/PERSONAL-CONTRACT-REVIEW.json",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 18284,
      "sha256": "9c1f44fd63b564fe9a5d0ee6eaeff2a22f34615b1abfd59d8efe23bd4154b4ae"
    },
    {
      "path": "docs/migration/effect-refactor/expansions/split-usage-desktop.json",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 139864,
      "sha256": "8aeedc538783d9e0373adec386f0bd9f1ce7a92c8a368c3d6ab2711e7ce2097f"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/cloud-fault-cases.json",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 78932,
      "sha256": "07a75cfe6624acec4a6a3f12cb8ae6f52d9fe1dc1b67339affd2566587b2d974"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/cloud-fault-model.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "bytes": 5423,
      "sha256": "02adec90b5b23bee196de9f9b6573e2a1f05537767ae36a9a39eb830b8d1492d"
    }
  ],
  "historical_donor12_source_pins": [
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/modules/scrollcost-screen-time/ios/ScrollCostScreenTimeModule.swift",
      "bytes": 23920,
      "sha256": "0cdfc76b5ac4cef45dcc0f76f30b16fbd4870f0d80971218655a4c2282911392",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/modules/scrollcost-screen-time/android/src/main/java/tech/isolated/scrollcost/screentime/UsageStatsReader.kt",
      "bytes": 3733,
      "sha256": "4ee09e0a0e44c62a15c77bbab4971d4654aa964f91b0c660b16b6cfaf5aba901",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/src/domain/usageFilters.ts",
      "bytes": 20951,
      "sha256": "5ecb5919ed70b56438e574cf3c7f3295dcded86f6dfba7bbcb3fc7282e2b22fd",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/src/domain/exports.ts",
      "bytes": 15978,
      "sha256": "2a5a2cdd358a84bc7508aaad2a919d2ee31c21a498e2000378852b2398bac80b",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/src/services/screenTime/nativeProvider.ts",
      "bytes": 5897,
      "sha256": "cd283408daab34c14788e8b957e2bb1ab264ae92e556043bad9f604c13ab0112",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/src/services/dailySnapshots/index.ts",
      "bytes": 8461,
      "sha256": "2a791db5cafb5bce4a4566aa66a047a0a373ebb0cb9c5050ee03f65691ec00a7",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/src/services/screenTime/types.ts",
      "bytes": 1414,
      "sha256": "26d084ec117318b0b01baaa396ef24616586a129c9b21b06c57b1e4f6f2aea44",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/App.tsx",
      "bytes": 95169,
      "sha256": "37b97a86f4f98fd068f2513714580702d3b8871dbd3fb24df6a41d4b22ec1a72",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/src/domain/exports.test.ts",
      "bytes": 4526,
      "sha256": "38cda5e73d6d1d944aa34af96a6daa1e77d17c32f13c71c83a568775cac07a9f",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/src/domain/usageFilters.test.ts",
      "bytes": 8789,
      "sha256": "5eeae80f517f5ddf4d95f4d8c3af4607d3e76800240aa7e7f1b32db8fbce4448",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "mobile/src/services/dailySnapshots/index.test.ts",
      "bytes": 2815,
      "sha256": "4476a0dd67bb80a62b6cde23f52d2af904b301cb41fb086ea4dd0b4fb83d413b",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    },
    {
      "repository": "time.md candidate",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "path": "LICENSE",
      "bytes": 34523,
      "sha256": "0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0",
      "scope": "source-only unadopted AGPL candidate; no runtime data"
    }
  ],
  "source_symbol_refs": [
    {
      "path": "mobile/modules/scrollcost-screen-time/ios/ScrollCostScreenTimeModule.swift",
      "line": 138,
      "symbol": "authorizationStatusString",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "line_sha256": "3a76828512622a5f0331869731e8d4bb015c41511aabe887ddfc2d0656dd9bd6"
    },
    {
      "path": "mobile/modules/scrollcost-screen-time/ios/ScrollCostScreenTimeModule.swift",
      "line": 176,
      "symbol": "deviceActivityUsage",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "line_sha256": "a689728163e456c7103b9be548e33f0f4181bd73c5b08069586f6efe9fe7d642"
    },
    {
      "path": "mobile/modules/scrollcost-screen-time/ios/ScrollCostScreenTimeModule.swift",
      "line": 278,
      "symbol": "detailedDeviceActivityUsage",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "line_sha256": "c7bc60c2d0bed52ed368c80dd2afd8fe3df522d147ef7bab9977b538ab3a3120"
    },
    {
      "path": "mobile/modules/scrollcost-screen-time/ios/ScrollCostScreenTimeModule.swift",
      "line": 357,
      "symbol": "detailRecord",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "line_sha256": "a2721d689092465a9cb30debcdacd3bc5ae1f0dc50ef32aad26f1e581710d6dc"
    },
    {
      "path": "mobile/modules/scrollcost-screen-time/ios/ScrollCostScreenTimeModule.swift",
      "line": 392,
      "symbol": "dateMilliseconds",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "line_sha256": "61fb747272e5d06725d55773d5396ba8f4a1b180906b290365c1eeb46793fdf9"
    },
    {
      "path": "mobile/src/services/screenTime/nativeProvider.ts",
      "line": 54,
      "symbol": "dayRange",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "line_sha256": "31c1d801b5786ce0186318fd1f7653461f557f59a2a6f3d5df3504ba4fc30211"
    },
    {
      "path": "mobile/src/services/screenTime/nativeProvider.ts",
      "line": 101,
      "symbol": "createNativeScreenTimeProvider",
      "source_revision": "2955ed07db9c649c77a128db59aed2ac0fef0bc5",
      "line_sha256": "e3c7e837afa8fa15a4feab52e53f40bf515f8015551d7412457d1174dfbf6bc1"
    }
  ],
  "selected_draft_refs": [
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/8",
      "case_id": "aggregate-not-session",
      "literal_canonical_sha256": "cb7f0173ca6a3ab2245275b512dfeaa0e3dd8d4d53e8c93ebef5312d711f8bb3"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/11",
      "case_id": "ios-exact-sessions-unestablished",
      "literal_canonical_sha256": "a2a97d737f8b89b59e2b95bc23b8c786842669bef4f7137a2fcfc3c3751ca63b"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/12",
      "case_id": "android-prototype-not-supported",
      "literal_canonical_sha256": "47411d804a59ed74b3205f2f85ba99372f9655cb8bcf6ea96d3bb68acaf664d0"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/13",
      "case_id": "unknown-empty-is-not-zero",
      "literal_canonical_sha256": "83e0a9f5ace445814e1575508a253af347f6fd6c713217ed5a535fb8e5e4b8c0"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/14",
      "case_id": "unavailable-empty-is-not-zero",
      "literal_canonical_sha256": "2e6b27d8f047263642529b42b7d23e2cfb7b3395ec1d242bed0c94c5e7528020"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/16",
      "case_id": "no-fabricated-completeness",
      "literal_canonical_sha256": "2418beab02f6fac7a1be42195aa180239eb8aec6728e7bc3d899a666b1edd251"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/17",
      "case_id": "hourly-daily-overlap",
      "literal_canonical_sha256": "838ec382cffc78d687b08810f327569cb6e3fd0fdbd75e6563754a94e1eee040"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/18",
      "case_id": "cross-device-overlap",
      "literal_canonical_sha256": "c7a9d059649e66b8a5e8af8bdfcb7401bb60d6a1a363c4817a304155d11b5dbe"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/19",
      "case_id": "same-key-same-bytes-replay",
      "literal_canonical_sha256": "1e3233d07c6425c1febf57cbde7f10d8c99349165aee49764e22f0d7ce51e6f9"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/20",
      "case_id": "same-key-different-bytes-conflict",
      "literal_canonical_sha256": "3ea36995edb9187346ea5f1c561b61709bc46b686580ca00b8813ae8133369f1"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/22",
      "case_id": "missing-donor-lineage",
      "literal_canonical_sha256": "385785580fbcbf40dd6a7c16cc4714673d9c0ac2a8daea7a4fa5564a61aa1054"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/26",
      "case_id": "browser-app-duration-allowed",
      "literal_canonical_sha256": "e0399e5317f38aef87d6450c168a4f06911db18c90e3c279178b6af7302f5373"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/29",
      "case_id": "excluded-import-before-staging",
      "literal_canonical_sha256": "c23ea76f29510236a54c430b412dc5360a2805d230448a83550ccab174ac056c"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/30",
      "case_id": "capture-not-export-grant",
      "literal_canonical_sha256": "3210c78665b669d91551002ea3b9d9ab98fd70abf2419e87ba4b5c9f4489c8a3"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/31",
      "case_id": "report-view-not-record-export",
      "literal_canonical_sha256": "9107f71fcf102b16b260f9cc2b77c6d7596fb965cd8cc485781123f58a1da353"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/34",
      "case_id": "strict-scope-denied-no-leak",
      "literal_canonical_sha256": "66a7720cee026fcdd409baf04f1f78f7d199b75b907555ca2a3f4a0264048b49"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/35",
      "case_id": "partial-scope-explicit",
      "literal_canonical_sha256": "16aaa4dcfe779d8188db0f9c1e2041de174288f0edce00848a15365d7b3b6d02"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/36",
      "case_id": "grant-revoked-during-page",
      "literal_canonical_sha256": "b9fe6bd3aed1bad5779bb74388667a26efd7a3dc0f470169069c86d06822c328"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/40",
      "case_id": "summary-not-complete-transfer",
      "literal_canonical_sha256": "4e1cc7579a34dca934c18505eec98ecbd4d9d9c7598fc49abbb78f30f57f3d29"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/41",
      "case_id": "complete-history-no-dashboard-cap",
      "literal_canonical_sha256": "e8a80fd74c63a1ed55528b46fded740d357a0e1d7c84d29e39064ec0d3ebf0ea"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/42",
      "case_id": "nonfinite-or-overprecision",
      "literal_canonical_sha256": "4ed5cf12d4adcff128f9d2de8f73f59f7db7b34c6d1c03f05e691a35094b3089"
    },
    {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/43",
      "case_id": "bounded-page-admission",
      "literal_canonical_sha256": "67192b632d6309009bf65faa154171b81bf7cc23377ce61dd74216cb3dba54c7"
    }
  ],
  "selected_design_row_pins": [
    {
      "id": "C14",
      "source_path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "reference_utf8_sha256": "20be7931afb48a2921c870eeb7198594068c8360edb77d3bc6f88550df61482f",
      "reference": "Source: docs/architecture/javascript-unified-layer-design-reference.md#contract-and-compatibility-coverage\n\n| C14 | Personal Data envelope/domain/store/capabilities | Independently versioned health/location/device_usage payloads, source/device identity, exact time/quality/provenance, annotations/inference/tombstones, capture/display/query/export status, independent domain/detail/destination grants. |"
    },
    {
      "id": "S01",
      "source_path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "reference_utf8_sha256": "48d0ac372fa20cf9bbae17763c6bb24d8525fb1c0d2d53b982439aca4f07736d",
      "reference": "Source: docs/architecture/javascript-unified-layer-design-reference.md#donor-migration-and-integration-work-packages\n\n| S01 — Mobile usage | iOS eligible historical aggregate/report adapters, multi-day backfill/durable reconciliation and qualified Android UsageStats/UsageEvents checkpoints. | Exact entitlement/purpose/destination matrix, production EU/region/one-app authorization, display-only fallback, past-date/full retained-range exports and source lookback/gaps, no today-only detail or false sessions. |"
    },
    {
      "id": "S03",
      "source_path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "reference_utf8_sha256": "affa188b654664608067662a1d60a4f2f2726232d2e89aa03b1a8a6744ffe6a0",
      "reference": "Source: docs/architecture/javascript-unified-layer-design-reference.md#donor-migration-and-integration-work-packages\n\n| S03 — Usage models and UI | Shared apps/trends/full-history/timeline/aggregate/detail/title views, categories/app assignments and source coverage. | No false iOS sessions/cross-device double counts; source-aware reducers and assignment revisions, missing versus empty titles, accessibility and bounded multi-year views. |"
    },
    {
      "id": "S06",
      "source_path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "reference_utf8_sha256": "ed9b9160389a5a951ac7583a3109809747ddbd60defb38e9e0f4874da798f4b8",
      "reference": "Source: docs/architecture/javascript-unified-layer-design-reference.md#donor-migration-and-integration-work-packages\n\n| S06 — Required exact iOS historical sessions | Follow-up exact per-app session/history contract and supported-source feasibility; implement when a permitted API can supply it. | Public API/purpose/destination proof, true observed app-session identities/boundaries/coverage, backfill and retained-range parity. Initial labeled aggregates do not close this row; unavailable API is explicitly recorded. |"
    },
    {
      "id": "F12",
      "source_path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "reference_utf8_sha256": "1d604218696ba4bc151e789dd581e76f96bd96a8b840cb2fd71ecfd8f14a3184",
      "reference": "Source: docs/architecture/javascript-unified-layer-design-reference.md#open-feasibility-decisions-and-risk-register\n\n| F12 | iOS usage production eligibility, purpose and export destinations | M02/S01 qualifies iOS 26.4+, entitlement, EU/device/account/one-app conditions and permitted destinations separately. Preserve report sandbox and display-only/unavailable outcomes; no development-profile proof or arbitrary MCP export claim. |"
    },
    {
      "id": "F16",
      "source_path": "docs/architecture/javascript-unified-layer-design-reference.md",
      "source_revision": "37580ca24a6d352d0ee2d8df2eca58e64e316d49",
      "reference_utf8_sha256": "3fa7ebdd1daaadaf2e9a05fd55d3eafdce9d6e6c1c2eec342dfd955a2a692d01",
      "reference": "Source: docs/architecture/javascript-unified-layer-design-reference.md#open-feasibility-decisions-and-risk-register\n\n| F16 | Full history versus source/API losses | S02/S04 retains all observed sessions beyond summaries and imports every available source record, declaring donor short-session/clock/crash/deletion gaps. S01 preserves historical aggregates; S06 remains required because no exact iOS app-session API is established. Aggregate shipping does not close it. |"
    }
  ],
  "all81_obligation_count": 81,
  "four_original_count": 4,
  "no_candidate_implementation_used": true
} as const;

export const iosUsageEligibilityPacketLiteralProposals = [
  {
    "case_id": "ios-approved-limited-report-only",
    "input": {
      "trusted_state": "approved",
      "purpose": "local_display",
      "requested": "data_read",
      "current_grants": "display_only"
    },
    "expected": {
      "result": "display_only",
      "data_acquires": 0,
      "export_allowed": false
    },
    "status": "independent literal proposal; full typed interface/vector freeze reviewed before implementation"
  },
  {
    "case_id": "ios-data-access-fake-route",
    "input": {
      "trusted_state": "approvedWithDataAccess",
      "sdk_profile": "synthetic_qualified",
      "purpose": "local_usage",
      "destination": "local_query",
      "current_grants": "source_detail_destination",
      "frontier": "current"
    },
    "expected": {
      "result": "aggregate_read_handoff",
      "acquires": 1,
      "native_qualification": false
    },
    "status": "independent literal proposal; full typed interface/vector freeze reviewed before implementation"
  },
  {
    "case_id": "ios-granted-source-denied-destination",
    "input": {
      "trusted_state": "approvedWithDataAccess",
      "current_source": true,
      "current_destination": false
    },
    "expected": {
      "result": "scope_not_authorized",
      "acquires": 0
    },
    "status": "independent literal proposal; full typed interface/vector freeze reviewed before implementation"
  },
  {
    "case_id": "ios-region-or-entitlement-unproven",
    "input": {
      "trusted_state": "approvedWithDataAccess",
      "host_admission": "unknown"
    },
    "expected": {
      "result": "unavailable",
      "acquires": 0,
      "zero_usage": false
    },
    "status": "independent literal proposal; full typed interface/vector freeze reviewed before implementation"
  },
  {
    "case_id": "ios-gate-cancel-owned",
    "input": {
      "cancel": "after_allocation_before_return",
      "cleanup": "acknowledged"
    },
    "expected": {
      "result": "interrupted",
      "allocations": 1,
      "releases": 1,
      "reads": 0
    },
    "status": "independent literal proposal; full typed interface/vector freeze reviewed before implementation"
  }
] as const;

export const iosUsageEligibilityImmutablePersonalObligations = [
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/0",
      "case_id": "combined-three-domains",
      "literal_canonical_sha256": "f787ae8ec7155b677d0e0d4d6d16711f8eff4624da4d833583644aa1921e15e7"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/1",
      "case_id": "health-scoped-same-dataset",
      "literal_canonical_sha256": "3031a7c2b73860641f414b4946155bec4cd9743720d94fa7b058db9ea2f8c0e0"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/2",
      "case_id": "point-binary64-lossless",
      "literal_canonical_sha256": "10380b0edcbafaa8b2ec9950e8d909b8cebf4e693aba7a4d37ffeb4d82b509df"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/3",
      "case_id": "health-large-integer-lossless",
      "literal_canonical_sha256": "6a0e08ded2ffd5b26bc1f6d107113d4fefb0e2f20f12af767626caf1650b6ee6"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/4",
      "case_id": "health-negativezero-preserve",
      "literal_canonical_sha256": "f19507b7a8e1f644e44ecd7407815db05a9ae6b1e492e460dafc08b889dedcbc"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/5",
      "case_id": "mixed-epoch-selection-precision",
      "literal_canonical_sha256": "22d0bac5ebb21bcb278c00d6c9beb24b21f5a47c3a63a93fe45275fbccdf196e"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/6",
      "case_id": "timestamp-nanos-order",
      "literal_canonical_sha256": "f0d696a9a37a118085bd7784356d4ae65df186d705c61290b1967c6a771e7e41"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/7",
      "case_id": "native-calendar-not-inferred",
      "literal_canonical_sha256": "ad412a2582682f9bd8ebc5ef733be1517c39dedd4c49e4f72d83ee80cbef17c5"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/8",
      "case_id": "aggregate-not-session",
      "literal_canonical_sha256": "cb7f0173ca6a3ab2245275b512dfeaa0e3dd8d4d53e8c93ebef5312d711f8bb3"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/9",
      "case_id": "short-session-retained",
      "literal_canonical_sha256": "1b46b83b9d42b8bebc1709bc53ed2b129762b134a5061b3e6e44246de5cfbd7a"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/10",
      "case_id": "historical-donor-short-tail-gap",
      "literal_canonical_sha256": "60ef53ac7d4c5ac219047d03e8d1766415cdec656ac22d21f0acfcf68c93ae38"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/11",
      "case_id": "ios-exact-sessions-unestablished",
      "literal_canonical_sha256": "a2a97d737f8b89b59e2b95bc23b8c786842669bef4f7137a2fcfc3c3751ca63b"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/12",
      "case_id": "android-prototype-not-supported",
      "literal_canonical_sha256": "47411d804a59ed74b3205f2f85ba99372f9655cb8bcf6ea96d3bb68acaf664d0"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/13",
      "case_id": "unknown-empty-is-not-zero",
      "literal_canonical_sha256": "83e0a9f5ace445814e1575508a253af347f6fd6c713217ed5a535fb8e5e4b8c0"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/14",
      "case_id": "unavailable-empty-is-not-zero",
      "literal_canonical_sha256": "2e6b27d8f047263642529b42b7d23e2cfb7b3395ec1d242bed0c94c5e7528020"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/15",
      "case_id": "observed-zero-only-evidence",
      "literal_canonical_sha256": "fc8ad14a33fdb4a30ad59e0ee7643f1caa19da3620207ea89289612afdd45824"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/16",
      "case_id": "no-fabricated-completeness",
      "literal_canonical_sha256": "2418beab02f6fac7a1be42195aa180239eb8aec6728e7bc3d899a666b1edd251"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/17",
      "case_id": "hourly-daily-overlap",
      "literal_canonical_sha256": "838ec382cffc78d687b08810f327569cb6e3fd0fdbd75e6563754a94e1eee040"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/18",
      "case_id": "cross-device-overlap",
      "literal_canonical_sha256": "c7a9d059649e66b8a5e8af8bdfcb7401bb60d6a1a363c4817a304155d11b5dbe"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/19",
      "case_id": "same-key-same-bytes-replay",
      "literal_canonical_sha256": "1e3233d07c6425c1febf57cbde7f10d8c99349165aee49764e22f0d7ce51e6f9"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/20",
      "case_id": "same-key-different-bytes-conflict",
      "literal_canonical_sha256": "3ea36995edb9187346ea5f1c561b61709bc46b686580ca00b8813ae8133369f1"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/21",
      "case_id": "new-install-not-same-device-history",
      "literal_canonical_sha256": "58a8cb3cdd59d3fd7bcfe5939cfe04e26ceb0dd99412dd0ace1ed431107d683f"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/22",
      "case_id": "missing-donor-lineage",
      "literal_canonical_sha256": "385785580fbcbf40dd6a7c16cc4714673d9c0ac2a8daea7a4fa5564a61aa1054"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/23",
      "case_id": "correction-preserves-original",
      "literal_canonical_sha256": "a46da9e1fcd062709b73ed02130cf9177d40a0dbf459957d2b1d5030ea039f4f"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/24",
      "case_id": "visit-sentinel-not-observed",
      "literal_canonical_sha256": "9a0c56d266fcf76300492f983825e49810ce28ddbbb6b8635b852ba02a3439e1"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/25",
      "case_id": "outing-not-recording",
      "literal_canonical_sha256": "327858fc1d295b03b4629a018c2b13b656a27c820c1b22a0fb4318972d3f98d7"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/26",
      "case_id": "browser-app-duration-allowed",
      "literal_canonical_sha256": "e0399e5317f38aef87d6450c168a4f06911db18c90e3c279178b6af7302f5373"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/27",
      "case_id": "browser-title-before-observation",
      "literal_canonical_sha256": "4e669bb96d68e8cf40d152a1493e0e93dafc577d6976aa277a4d5806c5151c6e"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/28",
      "case_id": "unknown-app-class-title-fails-closed",
      "literal_canonical_sha256": "0b60d6c3ec981d2a664242ff423d6bb66646699a2e99e618a30cb9f7438528fc"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/29",
      "case_id": "excluded-import-before-staging",
      "literal_canonical_sha256": "c23ea76f29510236a54c430b412dc5360a2805d230448a83550ccab174ac056c"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/30",
      "case_id": "capture-not-export-grant",
      "literal_canonical_sha256": "3210c78665b669d91551002ea3b9d9ab98fd70abf2419e87ba4b5c9f4489c8a3"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/31",
      "case_id": "report-view-not-record-export",
      "literal_canonical_sha256": "9107f71fcf102b16b260f9cc2b77c6d7596fb965cd8cc485781123f58a1da353"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/32",
      "case_id": "future-uploads-not-auto-agent-grant",
      "literal_canonical_sha256": "fedbb4a54ad04ae8317775db0cbd678f61d7c8d7f8bb6ebf7882f68cc4a722b5"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/33",
      "case_id": "title-query-not-agent-share",
      "literal_canonical_sha256": "e7ad6bbc0e7a697e0c1fb30b78960b5bc2af9a7881c8ccacf9704070cb3b6dee"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/34",
      "case_id": "strict-scope-denied-no-leak",
      "literal_canonical_sha256": "66a7720cee026fcdd409baf04f1f78f7d199b75b907555ca2a3f4a0264048b49"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/35",
      "case_id": "partial-scope-explicit",
      "literal_canonical_sha256": "16aaa4dcfe779d8188db0f9c1e2041de174288f0edce00848a15365d7b3b6d02"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/36",
      "case_id": "grant-revoked-during-page",
      "literal_canonical_sha256": "b9fe6bd3aed1bad5779bb74388667a26efd7a3dc0f470169069c86d06822c328"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/37",
      "case_id": "selector-cursor-crosswire",
      "literal_canonical_sha256": "a669d3c9957793bba406a2221c65e016a9ec6a053b89b7772378fcc57d5c3893"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/38",
      "case_id": "geographic-health-distance-distinct",
      "literal_canonical_sha256": "1678a10f57297bd75d3056ef81f4c97f7f77e8557bbc3247f58f20230486cca0"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/39",
      "case_id": "frozen-health-profiles",
      "literal_canonical_sha256": "3236101534d502f9e0e6325d25658f8bb51d3b7ddde6590cbb8db7f53eaf7671"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/40",
      "case_id": "summary-not-complete-transfer",
      "literal_canonical_sha256": "4e1cc7579a34dca934c18505eec98ecbd4d9d9c7598fc49abbb78f30f57f3d29"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/41",
      "case_id": "complete-history-no-dashboard-cap",
      "literal_canonical_sha256": "e8a80fd74c63a1ed55528b46fded740d357a0e1d7c84d29e39064ec0d3ebf0ea"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/42",
      "case_id": "nonfinite-or-overprecision",
      "literal_canonical_sha256": "4ed5cf12d4adcff128f9d2de8f73f59f7db7b34c6d1c03f05e691a35094b3089"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-cases.json",
      "pointer": "/cases/43",
      "case_id": "bounded-page-admission",
      "literal_canonical_sha256": "67192b632d6309009bf65faa154171b81bf7cc23377ce61dd74216cb3dba54c7"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/0",
      "case_id": "resolution-coordinate-endpoints",
      "literal_canonical_sha256": "6faec3d9871fe956fc0cf3cdea07a8a328ef4ba7a90242c40f8049712a171f52"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/1",
      "case_id": "resolution-coordinate-outside",
      "literal_canonical_sha256": "5cf5f3d0eff96d581735c1cbe05bfac149d98aa50824b9ab3be2c9e235b5c93e"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/2",
      "case_id": "resolution-nonfinite-coordinate",
      "literal_canonical_sha256": "5059d74fa470d94f329130427e9b300a56828dd710f50a06dfdee2a245aef5dd"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/3",
      "case_id": "resolution-negative-speed-sentinel",
      "literal_canonical_sha256": "af075f716ef13b882b2fe906541ffa9cfd85893d366fbe9b86e79b4563e55606"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/4",
      "case_id": "resolution-negative-accuracy-sentinel",
      "literal_canonical_sha256": "fe6cadb255c9575dc21b065d07ce76ed3343e80796e5ed0497dd5816a7b9805e"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/5",
      "case_id": "resolution-negativezero-speed",
      "literal_canonical_sha256": "0cac93e5767f546bdfea351fa8a09d6b6cfe31e57f1370216c0de72facf05219"
    },
    "literal": {
      "case_id": "resolution-negativezero-speed",
      "input": {
        "speed_bits": "8000000000000000"
      },
      "expected": {
        "canonical_status": "valid",
        "bits": "8000000000000000"
      }
    },
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/6",
      "case_id": "resolution-reversed-session",
      "literal_canonical_sha256": "9645055e3ea86a55d59e71ab04cc4144dea71f02791bd4ce23a362c39637be93"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/7",
      "case_id": "resolution-duration-disagreement",
      "literal_canonical_sha256": "204965c66f77710c4414fce25095481b4763c25b61648d40468964e18735c26a"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/8",
      "case_id": "resolution-zero-session",
      "literal_canonical_sha256": "22eb1b7eb4870585a103e5d30d2eb5e8b4c4e512c58d40e7bd59201746454fb9"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/9",
      "case_id": "resolution-original-record-equality",
      "literal_canonical_sha256": "7aab936d80d83056cfd2e08528d395217824e9c55b33316344b60225a314978f"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/10",
      "case_id": "resolution-lossy-equality-conflict",
      "literal_canonical_sha256": "330e2412c901d0e0299a7062cf0b5bc0c7d3f423ee77b98a333757778896ef99"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/11",
      "case_id": "resolution-repartition-key",
      "literal_canonical_sha256": "f3bf17b66877a3a493c6976d4d935ad47cf5e41d741bf0df0d5fbcce9faf07d8"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/12",
      "case_id": "resolution-missing-stable-import-order",
      "literal_canonical_sha256": "3702c6f0c6fd5b95eed3ffecffd8ed3eb6432d771fa7692da1d190533d6c6621"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/13",
      "case_id": "resolution-apple-unix-equality",
      "literal_canonical_sha256": "944d423f948b4cd0e09091848edcc34f6f0bcdb8134631b9d61f5d09b739822e"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/14",
      "case_id": "resolution-dyadic-subnanosecond",
      "literal_canonical_sha256": "f0d8b315335934a78d56b66cb69ddee73ccde7548eaa64abf7aad5f88eb0c754"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/15",
      "case_id": "resolution-half-open-end",
      "literal_canonical_sha256": "f2ec7a1113e2d91cd5af0b3d676c9f513859c0fe9f012a3d8cf444ae94f3ea19"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/16",
      "case_id": "resolution-negative-floor-nanos",
      "literal_canonical_sha256": "d08ea19527926ff4cf57981b9d2ff38ecaa917fbd3004cc26769a365da3b94a8"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/17",
      "case_id": "resolution-aggregate-partial-strict",
      "literal_canonical_sha256": "00cee5f268d671feab8344c0077bbcc1391ef0b1a041dade86f636928a8f34fb"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/18",
      "case_id": "resolution-aggregate-partial-allowed",
      "literal_canonical_sha256": "1208349cddbb7265d04ba299c4d92f5b4f2dd0c98b7efe0123800eb0d81ea255"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/19",
      "case_id": "resolution-aggregate-whole-context",
      "literal_canonical_sha256": "c4b1862e69405bb5302f82193c06aa8a53009dacdb563f7c5a783d9a6f696b1c"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/20",
      "case_id": "resolution-aggregate-context-denied",
      "literal_canonical_sha256": "ebc34c823dd5c4456f1e48b0641cde99998f1a050588cab230177b89be807870"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/21",
      "case_id": "resolution-observed-session-clip",
      "literal_canonical_sha256": "0b59ddaffee0ce743aaca4f7328332daec51142f11cc8ef9dac3e90932f4c771"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/22",
      "case_id": "resolution-tombstone-replay",
      "literal_canonical_sha256": "25645543c99c9d13ab76e1a57943369e227bec845395cf470b1f0e638945fbc5"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/23",
      "case_id": "resolution-correction-under-tombstone",
      "literal_canonical_sha256": "9b005f0f82a5a05269c5f0387890d676d85328154f8cacd8820bea0cdb51a330"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/24",
      "case_id": "resolution-delete-backup-regrant",
      "literal_canonical_sha256": "e6b8c1411044ff819bebaddfd1da1222b76df5939e375d0ac85227c09182d78a"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/25",
      "case_id": "resolution-frontier-changes-before-commit",
      "literal_canonical_sha256": "6a0910d4341bf8457c68121fed24cccd51d9e6d74c203c556f5db865e2821ae0"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/26",
      "case_id": "resolution-recipient-copy-limit",
      "literal_canonical_sha256": "30a9fc24305cf8765e2b20f4cf68b02cb421a19b5e1a551602729b4c39ad9308"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/27",
      "case_id": "resolution-schema-boolean-version",
      "literal_canonical_sha256": "803a49f4bff7795fa092066d8ec38036445240d5cd538bbc74c271c82053ab92"
    },
    "literal": {
      "case_id": "resolution-schema-boolean-version",
      "input": {
        "payload_revision": true
      },
      "expected": {
        "accept": false,
        "safe_code": "unsupported_shape"
      }
    },
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/28",
      "case_id": "resolution-unknown-source-field",
      "literal_canonical_sha256": "daf55c6fc52561174179efe94ed3150e2ca64728a9de84d4ec565cf3ca6c3f48"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/29",
      "case_id": "resolution-archive-excluded-title",
      "literal_canonical_sha256": "94e2aca6d083c92d3b058e52178213a8d296dcea2959f3c5eab008e67f53c895"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/30",
      "case_id": "resolution-reasonless-sensor-absent",
      "literal_canonical_sha256": "60954c1ab45c38292343eb26f11b598f15822a2f281980e4e59effd8603fb419"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/31",
      "case_id": "resolution-absent-sensor-wrong-value",
      "literal_canonical_sha256": "ebcce515b7a46e59ec57a103dda3556a56f2758ac1c821f5f1f7c5df07202a9b"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/32",
      "case_id": "resolution-native-source-rounded-subtraction",
      "literal_canonical_sha256": "44ebec079ad913c8cdb1e5382f4c09356298830e6bead65281f84a891458238a"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/33",
      "case_id": "resolution-delete-restore-denied",
      "literal_canonical_sha256": "f42d508db343cb79d071012da8afcb4eb4d6115ae12a15d346b1cbc461ef37b9"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/34",
      "case_id": "resolution-authoritative-frontier-restore-denied",
      "literal_canonical_sha256": "a55a17ed8a5f5a85a9ffb2911dc70d9b882a1541a6d9b7e8d25c27d979787391"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/35",
      "case_id": "resolution-local-tombstone-reversible-only",
      "literal_canonical_sha256": "a6375c3780945cea98729db86262684bd7c4730c488cd86978b258216c90f49a"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  },
  {
    "reference": {
      "path": "docs/migration/effect-refactor/decisions/personal-contract-resolution.md",
      "embedded_json_pointer": "/36",
      "case_id": "resolution-unrepresentable-clipped-duration",
      "literal_canonical_sha256": "d0392c865c66dd522b5cabb9fa6f633ae896df5b990d116185e921df0f1f334f"
    },
    "literal": {
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
    "gate_qualification": "immutable retained obligation; only scoped gate obligations exercised here, no all-family implementation qualification"
  }
] as const;

export const iosUsageEligibilityFourOriginalRecords = [
  {
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
  {
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
  {
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
  {
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
  }
] as const;

export const iosUsageEligibilityVectors = [
  {
    "case_id": "gate-synthetic-data-access",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "approvedWithDataAccess_qualified",
        "source": "permitted",
        "current": "permitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-approved-display-fallback",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"requested\":\"data_read\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "purpose": "local_display",
          "destination": "local_report"
        },
        "catalog": "approved_display_only",
        "source": "display_permitted",
        "current": "display_permitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"requested\":\"data_read\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approved\",\"route\":\"display_only\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "display_only",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-request-explicit-report",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"requested\":\"report_display\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "purpose": "local_display",
          "destination": "local_report",
          "requested": "report_display"
        },
        "catalog": "approved_display_only"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"requested\":\"report_display\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approved\",\"route\":\"display_only\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "display_only",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-denied",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "denied"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"denied\",\"route\":\"unavailable\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-notDetermined",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "notDetermined"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"notDetermined\",\"route\":\"unavailable\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-unknown",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "unknown"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"unavailable\",\"route\":\"unavailable\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-unproven_region_account_entitlement",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "unproven_region_account_entitlement"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"unavailable\",\"admission\":\"unproven\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-unsupported_api",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "unsupported_api"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"unavailable\",\"admission\":\"unproven\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-source_profile_unadmitted",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "source_profile_unadmitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "source_profile_unadmitted",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-denied-source",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_or_current_denied": "source"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-denied-purpose",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_or_current_denied": "purpose"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-denied-detail",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_or_current_denied": "detail"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-denied-query",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_or_current_denied": "query"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-denied-destination",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_or_current_denied": "destination"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-denied-job",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_or_current_denied": "job"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-denied-display",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_or_current_denied": "display"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-excluded-browser_url",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"browser_url\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "browser_url"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"browser_url\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"browser_url\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-web_domain",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"web_domain\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "web_domain"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"web_domain\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"web_domain\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-browser_path",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"browser_path\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "browser_path"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"browser_path\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"browser_path\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-visits",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"visits\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "visits"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"visits\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"visits\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-history",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"history\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "history"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"history\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"history\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-tab_title",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"tab_title\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "tab_title"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"tab_title\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"tab_title\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-window_title",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"window_title\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "window_title"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"window_title\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"window_title\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-input",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"input\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "input"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"input\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"input\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-keystroke",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"keystroke\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "keystroke"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"keystroke\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"keystroke\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-excluded-cursor",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"cursor\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "cursor"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"cursor\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"cursor\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-browser-app-duration",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "trusted_app_class": "browser",
        "detail": "app_duration",
        "excluded_api_traps": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-missing-label-app-not-omitted",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "trusted_app_label": "absent",
        "trusted_app_identity": "known"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-unknown-class-title",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"window_title\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "detail": "window_title"
        },
        "trusted_app_class": "unknown"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"window_title\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"window_title\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-argument-plain_object",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "plain_object"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-throwing_accessor",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "throwing_accessor"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-throwing_proxy",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "throwing_proxy"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-revoked_proxy",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "revoked_proxy"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-string_object",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "string_object"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-number",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "number"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-boolean",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "boolean"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-null",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "null"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-array",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "array"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-symbol",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "symbol"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-argument-function",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_argument_kind": "function"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-request-unknown_field",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"unknown\":true}",
      "scenario": {
        "request_mutation": "unknown_field"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-entitlement_flag",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"entitlement\":true}",
      "scenario": {
        "request_mutation": "entitlement_flag"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-authorization_flag",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorized\":true}",
      "scenario": {
        "request_mutation": "authorization_flag"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-frontier_flag",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"frontier_revision\":\"999\"}",
      "scenario": {
        "request_mutation": "frontier_flag"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-missing_field",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "missing_field"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-wrong_field_type",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":true,\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "wrong_field_type"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-duplicate_key",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"job_id\":\"synthetic-job-a\"}",
      "scenario": {
        "request_mutation": "duplicate_key"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-escaped_duplicate_key",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"job\\u005fid\":\"synthetic-job-a\"}",
      "scenario": {
        "request_mutation": "escaped_duplicate_key"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-nested_value",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":{\"nested\":\"value\"},\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "nested_value"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-trailing_data",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096} false",
      "scenario": {
        "request_mutation": "trailing_data"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-unpaired_surrogate",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"\\ud800\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "unpaired_surrogate"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-nul",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"\\u0000\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "nul"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-incomplete_escape",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":409\\",
      "scenario": {
        "request_mutation": "incomplete_escape"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-noncanonical_integer",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":1.0,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "noncanonical_integer"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-rounded_fraction",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":1.00000000000000000001,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "rounded_fraction"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-underflow_number",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":1e-999,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "underflow_number"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-unadmitted-profile",
    "input": {
      "request_json": "{\"profile\":\"native.ios.deviceactivity\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "profile": "native.ios.deviceactivity"
        }
      },
      "catalog_binding_json": "{\"profile\":\"native.ios.deviceactivity\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "source_profile_unadmitted",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-raw_utf8_4097",
    "input": {
      "request_json": "ééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééa",
      "scenario": {
        "request_mutation": "raw_utf8_4097"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-giant_primitive",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "giant_primitive"
      },
      "primitive_builder": {
        "unit": "a",
        "repeat_count": 65537,
        "result_type": "primitive_string",
        "purpose": "Check code-unit limit before UTF8 buffer/token allocation"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-depth5",
    "input": {
      "request_json": "{\"job_id\":{\"a\":{\"b\":{\"c\":{\"d\":\"x\"}}}}}",
      "scenario": {
        "request_mutation": "depth5"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-nodes65",
    "input": {
      "request_json": "[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]",
      "scenario": {
        "request_mutation": "nodes65"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-identifier129",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "identifier129"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-page33",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":33,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "page33"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-records4097",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4097}",
      "scenario": {
        "request_mutation": "records4097"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-page0",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":0,\"record_limit\":4096}",
      "scenario": {
        "request_mutation": "page0"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-bound-records0",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":0}",
      "scenario": {
        "request_mutation": "records0"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "candidate_limit_exceeded",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-request-limits-exact",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 ",
      "scenario": {
        "request_mutation": "canonical_whitespace_raw4096",
        "request_changes": {
          "page_limit": 32,
          "record_limit": 4096
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-object_argument",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "object_argument"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-duplicate_key",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "duplicate_key"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-unknown_field",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "unknown_field"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-unpaired_surrogate",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "unpaired_surrogate"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-oversize4097",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "oversize4097"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-wrong_type",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "wrong_type"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-wrong_authorization_state",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "wrong_authorization_state"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-wrong_route",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "wrong_route"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-noncanonical_frontier",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "noncanonical_frontier"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-binding-wrong_page_limit",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog_binding_mutation": "wrong_page_limit"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-source_id",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "source_id"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-source_revision",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "source_revision"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-installation_id",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "installation_id"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-purpose",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "purpose"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-destination",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "destination"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-job_id",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "job_id"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-selection_id",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "selection_id"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-detail",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "detail"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-proof_ref",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "proof_ref"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-crosswire-frontier_lineage",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "binding_or_current_crosswire": "frontier_lineage"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_allocation-destination",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_allocation",
          "revokes": "destination"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_allocation-job",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_allocation",
          "revokes": "job"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_allocation-source",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_allocation",
          "revokes": "source"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_allocation-detail",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_allocation",
          "revokes": "detail"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_allocation-delete_frontier",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_allocation",
          "revokes": "delete_frontier"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_publication-destination",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_publication",
          "revokes": "destination"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_publication-job",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_publication",
          "revokes": "job"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_publication-source",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_publication",
          "revokes": "source"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_publication-detail",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_publication",
          "revokes": "detail"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-before_publication-delete_frontier",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "before_publication",
          "revokes": "delete_frontier"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-assert_current-destination",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "assert_current",
          "revokes": "destination"
        },
        "assert_current": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-assert_current-job",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "assert_current",
          "revokes": "job"
        },
        "assert_current": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-assert_current-source",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "assert_current",
          "revokes": "source"
        },
        "assert_current": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-assert_current-detail",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "assert_current",
          "revokes": "detail"
        },
        "assert_current": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-reentry-assert_current-delete_frontier",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_callback_reentry": {
          "phase": "assert_current",
          "revokes": "delete_frontier"
        },
        "assert_current": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-missing",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "missing"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-stale",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "stale"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-wrong_lineage",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "wrong_lineage"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-incomplete",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "incomplete"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-self_declared_latest",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "self_declared_latest"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-old_backup_after_delete",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "old_backup_after_delete"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-regrant_after_revoke",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "regrant_after_revoke"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-undo_after_delete",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "undo_after_delete"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-rekey_old_evidence",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "rekey_old_evidence"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-frontier-advances-after-allocation",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_external_frontier": "advance_before_publication"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-cancel-before-allocation",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "cancel": "during_resolve",
        "cleanup": "none"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "interrupted",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-cancel-after-allocation",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "cancel": "after_allocation_before_publication",
        "cleanup": "acknowledged"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "interrupted",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-cancel-waits-cleanup",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "cancel": "after_allocation_before_publication",
        "cleanup": "delayed_ack_signal"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "interrupted",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "completion_before_ack": false
    }
  },
  {
    "case_id": "gate-release-fault",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "cleanup": "provider_failure"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "cleanup_unacknowledged",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 0,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-cancel-cleanup-defect",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "cancel": "after_allocation_before_publication",
        "cleanup": "defect_with_sensitive_reason"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "interrupted",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "safe_causes": [
        "interrupt",
        "cleanup_unacknowledged"
      ],
      "provider_reason_visible": false
    }
  },
  {
    "case_id": "gate-provider-failure-resolve",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "provider_fault": "resolve"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "provider_reason_visible": false
    }
  },
  {
    "case_id": "gate-provider-failure-source_check",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "provider_fault": "source_check"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "provider_reason_visible": false
    }
  },
  {
    "case_id": "gate-provider-failure-current",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "provider_fault": "current"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "provider_reason_visible": false
    }
  },
  {
    "case_id": "gate-provider-failure-allocate",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "provider_fault": "allocate"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "provider_reason_visible": false
    }
  },
  {
    "case_id": "gate-assert-after-close",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_after_scope_close": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "owned_handoff_closed",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls_after_close": 0
    }
  },
  {
    "case_id": "gate-assert-crosswire",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_request_changes": {
          "job_id": "synthetic-job-b"
        }
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls_for_crosswire_assert": 0
    }
  },
  {
    "case_id": "gate-assert-same-request-order",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_json_member_order": "reversed"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-assert-revoked-proxy",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_argument_kind": "revoked_proxy"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "argument_traps": 0
    }
  },
  {
    "case_id": "gate-one-pending-handoff",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "concurrent_second_open": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "second_result": "candidate_limit_exceeded",
      "second_allocations": 0
    }
  },
  {
    "case_id": "gate-cleanup-poisons-slot",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "cleanup": "provider_failure",
        "second_open_after_cleanup_failure": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "cleanup_unacknowledged",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 0,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "second_result": "cleanup_unacknowledged",
      "second_host_calls": 0
    }
  },
  {
    "case_id": "gate-ack-frees-slot",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "sequential_second_open": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 2,
      "releases": 2,
      "acknowledged_releases": 2,
      "handoffs": 2,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-no-history-claim-empty_unknown",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_history_metadata": "empty_unknown"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "observed_zero": false,
      "complete_history": false,
      "exact_sessions": false
    }
  },
  {
    "case_id": "gate-no-history-claim-empty_unavailable",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_history_metadata": "empty_unavailable"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "observed_zero": false,
      "complete_history": false,
      "exact_sessions": false
    }
  },
  {
    "case_id": "gate-no-history-claim-traversal_exhaustion",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_history_metadata": "traversal_exhaustion"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "observed_zero": false,
      "complete_history": false,
      "exact_sessions": false
    }
  },
  {
    "case_id": "gate-no-history-claim-today_refresh",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_history_metadata": "today_refresh"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "observed_zero": false,
      "complete_history": false,
      "exact_sessions": false
    }
  },
  {
    "case_id": "gate-no-history-claim-370_key_snapshot",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_history_metadata": "370_key_snapshot"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "observed_zero": false,
      "complete_history": false,
      "exact_sessions": false
    }
  },
  {
    "case_id": "gate-no-history-claim-400_day_relay",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_history_metadata": "400_day_relay"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "observed_zero": false,
      "complete_history": false,
      "exact_sessions": false
    }
  },
  {
    "case_id": "ios-approved-limited-report-only",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"requested\":\"data_read\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "request_changes": {
          "purpose": "local_display",
          "destination": "local_report"
        },
        "catalog": "approved_display_only",
        "source": "display_permitted",
        "current": "display_permitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"requested\":\"data_read\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approved\",\"route\":\"display_only\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_display\",\"destination\":\"local_report\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "display_only",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "data_acquires": 0
    },
    "packet_proposal_input": {
      "trusted_state": "approved",
      "purpose": "local_display",
      "requested": "data_read",
      "current_grants": "display_only"
    },
    "packet_expected_literal": {
      "result": "display_only",
      "data_acquires": 0,
      "export_allowed": false
    }
  },
  {
    "case_id": "ios-data-access-fake-route",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "approvedWithDataAccess_qualified",
        "source": "permitted",
        "current": "permitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "acquires": 1
    },
    "packet_proposal_input": {
      "trusted_state": "approvedWithDataAccess",
      "sdk_profile": "synthetic_qualified",
      "purpose": "local_usage",
      "destination": "local_query",
      "current_grants": "source_detail_destination",
      "frontier": "current"
    },
    "packet_expected_literal": {
      "result": "aggregate_read_handoff",
      "acquires": 1,
      "native_qualification": false
    }
  },
  {
    "case_id": "ios-granted-source-denied-destination",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "source_or_current_denied": "destination"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "acquires": 0
    },
    "packet_proposal_input": {
      "trusted_state": "approvedWithDataAccess",
      "current_source": true,
      "current_destination": false
    },
    "packet_expected_literal": {
      "result": "scope_not_authorized",
      "acquires": 0
    }
  },
  {
    "case_id": "ios-region-or-entitlement-unproven",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "catalog": "unproven_region_account_entitlement"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"unavailable\",\"admission\":\"unproven\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unavailable",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "acquires": 0,
      "zero_usage": false
    },
    "packet_proposal_input": {
      "trusted_state": "approvedWithDataAccess",
      "host_admission": "unknown"
    },
    "packet_expected_literal": {
      "result": "unavailable",
      "acquires": 0,
      "zero_usage": false
    }
  },
  {
    "case_id": "ios-gate-cancel-owned",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "cancel": "after_allocation_before_publication",
        "cleanup": "acknowledged"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "interrupted",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    },
    "packet_proposal_input": {
      "cancel": "after_allocation_before_return",
      "cleanup": "acknowledged"
    },
    "packet_expected_literal": {
      "result": "interrupted",
      "allocations": 1,
      "releases": 1,
      "reads": 0
    }
  },
  {
    "case_id": "gate-exact-utf8-bound-invalid-json",
    "input": {
      "request_json": "éééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééééé",
      "scenario": {
        "request_mutation": "exact4096_not_json"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "unsupported_request",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls": 0
    }
  },
  {
    "case_id": "gate-grant-revision-advances-before-publication",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_revision_change": "after_allocate_before_publication",
        "permission_remains": "permitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "3",
          "frontier_revision": "7",
          "decision": "permitted"
        },
        "before_publication": {
          "grant_revision": "4",
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revision-advances-after-publication",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_current": true,
        "current_authority_revision_change": "after_publication",
        "permission_remains": "permitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "3",
          "frontier_revision": "7",
          "decision": "permitted"
        },
        "before_publication": {
          "grant_revision": "3",
          "frontier_revision": "7",
          "decision": "permitted"
        },
        "assert_current": {
          "grant_revision": "4",
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revoke-regrant-cannot-repin",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_current": true,
        "trusted_revoke_then_regrant": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "3",
          "frontier_revision": "7",
          "decision": "permitted"
        },
        "before_publication": {
          "grant_revision": "3",
          "frontier_revision": "7",
          "decision": "permitted"
        },
        "revoke_intermediate": {
          "grant_revision": "4",
          "frontier_revision": "7",
          "decision": "scope_not_authorized"
        },
        "assert_current": {
          "grant_revision": "5",
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_binding_mismatch",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-denial-precedes-revision-mismatch",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_revision_change": "after_allocate_before_publication",
        "permission_remains": "scope_not_authorized"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "3",
          "frontier_revision": "7",
          "decision": "permitted"
        },
        "before_publication": {
          "grant_revision": "4",
          "frontier_revision": "8",
          "decision": "scope_not_authorized"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revision-invalid-leading-zero",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_invalid_grant_revision": "03"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "03",
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revision-invalid-overflow",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_invalid_grant_revision": "18446744073709551616"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "18446744073709551616",
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revision-invalid-numeric-json",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_invalid_grant_revision": 3
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": 3,
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revision-invalid-boolean-json",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_invalid_grant_revision": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": true,
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revision-invalid-fraction-string",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_invalid_grant_revision": "3.0"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "3.0",
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revision-invalid-exponent-string",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_invalid_grant_revision": "3e0"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "3e0",
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "invalid_host_binding",
      "allocations": 0,
      "releases": 0,
      "acknowledged_releases": 0,
      "handoffs": 0,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-grant-revision-u64-max-exact",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "current_authority_grant_revision": "18446744073709551615"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use.",
      "current_revision_schedule": {
        "before_allocation": {
          "grant_revision": "18446744073709551615",
          "frontier_revision": "7",
          "decision": "permitted"
        },
        "before_publication": {
          "grant_revision": "18446744073709551615",
          "frontier_revision": "7",
          "decision": "permitted"
        },
        "assert_current": {
          "grant_revision": "18446744073709551615",
          "frontier_revision": "7",
          "decision": "permitted"
        }
      }
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "aggregate_read_handoff",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false
    }
  },
  {
    "case_id": "gate-captured-services-cannot-reprovide",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_current": true,
        "original_current_denied": true,
        "reprovided_current": "permitted",
        "reprovided_catalog": "permitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "scope_not_authorized",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "reprovided_service_calls": 0
    }
  },
  {
    "case_id": "gate-escaped-closed-handoff-cannot-reprovide",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_after_scope_close": true,
        "new_scope": true,
        "reprovided_current": "permitted",
        "reprovided_catalog": "permitted"
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "owned_handoff_closed",
      "allocations": 1,
      "releases": 1,
      "acknowledged_releases": 1,
      "handoffs": 1,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "host_calls_after_close": 0,
      "reprovided_service_calls": 0
    }
  },
  {
    "case_id": "gate-old-handoff-not-reactivated-by-new-open",
    "input": {
      "request_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096}",
      "scenario": {
        "assert_after_scope_close": true,
        "new_same_request_handoff_open": true
      },
      "catalog_binding_json": "{\"profile\":\"synthetic.ios.usage.eligibility.v1\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"requested\":\"data_read\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"page_limit\":32,\"record_limit\":4096,\"authorization_state\":\"approvedWithDataAccess\",\"route\":\"aggregate_read_handoff\",\"admission\":\"synthetic_qualified\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\"}",
      "current_json": "{\"decision\":\"permitted\",\"source_id\":\"synthetic-ios-source-a\",\"source_revision\":\"synthetic-contract1\",\"installation_id\":\"synthetic-install-a\",\"purpose\":\"local_usage\",\"destination\":\"local_query\",\"job_id\":\"synthetic-job-a\",\"selection_id\":\"synthetic-selection-a\",\"detail\":\"app_duration\",\"proof_ref\":\"synthetic-installed-channel-proof-a\",\"frontier_lineage\":\"synthetic-suppression-a\",\"frontier_revision\":\"7\",\"grant_revision\":\"3\"}",
      "scenario_contract": "Named reentry/fault/signal/argument fixtures describe owned fake behavior; no caller JSON flags establish runtime authority. Raw request/binding/current strings are literal baselines; specific binding/current mutation is the stated independent hostile-host stimulus before use."
    },
    "procedure": "Run open with owned fake Layers in Effect.scoped; optional assertCurrent steps before/after scoped exit; collect only sanitized fixed outcome/counters. No actual platform source.",
    "expected": {
      "result": "owned_handoff_closed",
      "allocations": 2,
      "releases": 2,
      "acknowledged_releases": 2,
      "handoffs": 2,
      "reads": 0,
      "personal_materializations": 0,
      "deliveries": 0,
      "web_observations": 0,
      "title_observations": 0,
      "input_observations": 0,
      "persistent_private_state_writes": 0,
      "native_qualification": false,
      "export_allowed": false,
      "reprovided_service_calls": 0,
      "old_handoff_result": "owned_handoff_closed",
      "old_handoff_authority_calls_after_close": 0
    }
  }
] as const;
