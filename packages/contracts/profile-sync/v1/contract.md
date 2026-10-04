# Health.md profile-sync v1 (proposed source contract)

**Proposed / deferred source registration / synthetic-first / inactive and not shipped.** AS05 adds codecs and conformance artifacts, not synchronization, native reconciliation, account authorization, persistence, a privacy policy, or rollout approval. AS01's [source design](../../../../docs/architecture/account-profile-sync-source-design.md) and [approval ledger](../../../../docs/architecture/account-sync-evidence-ledger.md) remain governing. Live registrations/adapters/privacy and product/mobile/physical approvals remain unavailable. AS18 is undecided.

Outcome: explicitly selected portable profiles can eventually be published and reviewed across devices without copying local execution authority. Signing in transfers zero profiles. Sync does not read HealthKit/Health Connect, query providers, upload exports, activate profiles/schedules, grant request/MCP/read/upload authority, or alter charts or frozen work.

## Independent representation and scope

Transport: `schema: "healthmd.profile_sync"`, lexical integer `schema_version: 1`, bounded UTF-8 JSON. [Transport schema](profile-sync.schema.json) describes records, mutations, reads, pages and fixed errors. [Portable schema](portable-content.schema.json) is an independently CLOSED projection of the frozen [Shared Setup v2](../../shared-setup/v2/contract.md) profile fields. Neither schema is a replacement for the parsers' lexical, security, registry and cross-field checks.

Content is a UTF-8 JSON **string** in `content_json`, not an arbitrary native snapshot, v2 bundle, JSON object that an adapter may reserialize, or base64 health export. Its own grammar is:

```text
schema = healthmd.profile_sync.portable
schema_version = lexical integer 1
origin_platform = apple | android (descriptive, never authority)
metric_registry = exact v2 registry-identity shape
metric_aliases = exact sorted per-profile alias union
profile = name, export, metrics, presentation, individual_entries,
          daily_notes, destination, schedule, platform_extensions
```

There is no `bundle_id`, `active_profile`, `created_by`, native ID, account ID, app-global preferences, execution snapshot, or health payload inside this projection. At least the declared origin's typed v2 extension is non-null. Foreign typed extensions retain their own exact meanings. Origin is not proof of authorship, platform permission, account ownership or foreign-edit eligibility.

### Exact reuse and independent safety tightening

`source-pins.json` pins the existing schema and registry bytes. Python reuses the frozen v2 schema interpreter, writer allowlist, recursive security scan, path validator and registry validator. It does **not** call the fixture-only endpoint helper that restricts canonical v2 test fixtures to `setup.invalid`. TS embeds the same closed field definitions, security deny data and all 248 exact registry alias rows. Native codecs run their own strict preflight/closed shape plus the actual existing v2 typed codec on a synthesized one-profile validation witness. Its `profile-001`/active reference exists only inside that write-free witness; it is never sync/native identity or apply protocol.

V1 intentionally tightens these cases without editing v2:

- Unknown fields/enum values/extensions fail closed, including optional fields v2 readers might ignore. There is no lossy future-field persistence or replacement.
- Every numeric token is an integer: no Boolean-as-number, decimal, exponent, `-0`, non-finite value, string/null revision or value beyond `2^53-1`.
- Missing required nullable fields fail; null is not absence. Empty relative path components, including a trailing slash, fail.
- Common and Apple schedule presence/cadence must agree whenever Apple is present, including foreign preservation. A native client unable to edit both meanings must preserve them unchanged and report requires-action.
- Short frontmatter labels/identifiers exclude U+0000–001F and U+007F. Profile names use an explicit finite v1 scalar policy before native v2 reuse, never a platform `strip`/`trim`: reject edge U+0009–000D, U+0020, U+0085 (NEL), U+00A0, U+1680, U+2000–200A, U+2028–2029, U+202F, U+205F, U+3000 and U+FEFF (BOM). Reject U+0000–001F, U+007F, U+0085, U+2028 and U+2029 anywhere in a name (the last three are Unicode line breaks rejected by the frozen Apple short-string validator). No Unicode-property/locale/version-dependent whitespace lookup is authority here. Accepted names retain exact original scalar spelling and bytes, including composed/decomposed text and non-whitespace format scalars U+180E/U+200B/U+2060; never normalize or trim. This finite source subset repairs the evidenced Python NEL/JS BOM differential without rewriting v2 or claiming product naming approval.
- Endpoint hints use literal ASCII RFC3986 path characters only, with no percent, query, fragment, userinfo, backslash, raw space, non-ASCII path or network-path prefix. This is a reversible source safety choice: frozen Apple v2's `percentEncodedPath` setter can trap on otherwise schema-shaped raw characters. Such existing intent remains local/requires-action; do not normalize/drop it or claim product approval for the narrower v1 subset.
- Native identity/path/credential-looking material in user-authored strings is rejected using the shared negative corpus. This is not a guarantee that arbitrary prose contains no private data.
- Object keys are unique after decoded Unicode **NFC comparison**, including escaped key aliases. Reject ambiguous canonically equivalent keys; never rewrite them. This prevents Swift dictionaries silently merging distinct scalar sequences. Other strings, names and content bytes are not normalized or case-folded.

All v1 objects are closed, except the explicitly typed `custom_values` and individual metric maps. New portable neutral Today Refresh fields are not invented: Android's frozen-v2 local-only scope and Apple's typed intent are retained unchanged. HealthKit archive and Android raw snapshot preferences remain distinct, never aliased.

## Bounds and hashing (proposed source choices, not retention promises)

- Content input: at most **262,144 encoded bytes**.
- Transport input/output: at most **4,194,304 encoded bytes**; read request and fixed-error response at most **8,192 bytes**.
- Root depth 0, maximum depth 20, maximum 512 members/items per container, 16,384 JSON value nodes, 65,536 scalars per key/content string. Transport strings may hold the bounded nested JSON text; nested content gets its own stricter checks.
- All integers fit `0...9007199254740991` where nonnegative; revisions/sequences start at 1. Content field ranges, arrays and path/template caps otherwise reuse v2. Raw UTF-8, duplicate keys, surrogate pairs and size are checked before lossy versioned decoding. A UTF-8 BOM and trailing non-whitespace data fail.
- Pages contain at most 8 items, and must also fit the aggregate byte bound. Server shrinks a page to fit; it never splits/reformats a content string.

Content digest is lowercase hex:

```text
SHA256(UTF8("healthmd.profile_sync.portable/v1") || 0x00 || EXACT_CONTENT_UTF8_BYTES)
```

The hash covers the complete content grammar including registry/aliases/origin/foreign extensions. It does not cover outer object revision/order/account context. There is **no canonicalization**: key ordering, whitespace, escapes, Unicode scalar spelling and a trailing LF are significant bytes. The fixture builder uses sorted compact JSON plus LF merely for reproducibility. Removing LF or reserializing creates a different digest. Accepted content must retain the original byte/string representation. No arbitrary Swift/Kotlin/TS serializer output is called canonical.

Idempotency request fingerprint is independently domain-separated:

```text
SHA256(UTF8("healthmd.profile_sync.mutate/v1") || 0x00 || EXACT_MUTATION_REQUEST_UTF8_BYTES)
```

Persist and retry the original request bytes, not a reconstructed DTO. Reordering keys/whitespace with an already used mutation ID is a mismatch. Parsers expose a locally computed request hash, not a caller-trusted wire field. A digest is integrity/reference data, not authorization, a signature, consent or execution approval.

## Stable identity, immutable content and total order

A `profile_id` is `psp_` plus 32 lowercase hexadecimal characters, issued using server entropy and uniqueness checks in one authenticated account/environment. Client create cannot choose it. A native profile ID is separately generated locally; names and bundle `profile-NNN` are never mapping/merge keys. Names are retained verbatim and can be identical, including case/Unicode-related spellings. UI disambiguates by object reference, not an invented cross-platform case-fold algorithm or automatic cloud rename. A native store's unique-name restriction needs a separately reviewed local display alias/projection; it must not change synced name bytes or identity. If no truthful bounded native representation exists, adoption stops requires-action before visibility. AS08/AS09 own that adapter and its tests.

A live record has exactly:

```text
schema, schema_version, profile_id, object_revision, event_sequence,
order_key, deleted=false, content_revision, content_hash, content_json
```

- `object_revision`: per-object server CAS generation, starting at 1 and strictly increasing on effective changes.
- `event_sequence`: per-account/environment strictly increasing server change sequence. Never native time or a content ID.
- `content_revision`: per-object immutable content generation, starting at 1 and no greater than object revision. It changes only when exact content bytes change; reorder cannot rewrite it.
- `order_key`: nonnegative integer; total live order is ascending `(order_key, profile_id)` using ASCII opaque-ID ordering. Ties are permitted and deterministic. Reorder changes metadata only, not native active selection or schedules.

The immutable reference is `(trusted owner context, profile_id, content_revision, content_hash)` plus validated exact content. It is not a native approved execution reference. Private constructors/TS runtime brands prevent a normal caller fabricating validated content/references from unchecked JSON. Such a parsed reference still proves neither server issuance/ownership nor local acceptance; those come from separate adapters/review.

A tombstone has the same metadata shape with `deleted=true`; `order_key`, `content_revision`, `content_hash`, `content_json` are explicitly null. Retired IDs are never reassigned during the account lifecycle. No update, reorder or delete turns a tombstone/unknown ID into a live row. Keep-both/republish uses a new create and new ID. Account erasure, tombstone/event/idempotency/cursor expiry and retired-ID allocation are AS06/privacy-policy gates, not an eternal-retention promise made here.

## Conditional/idempotent mutations

Every mutation requires `operation`, opaque `mutation_id` (`psm_` + 32 lowercase hex) and explicit `base_revision` in the transport envelope. Unknown/caller-account/native IDs, credentials and fields fail closed.

| Operation | Required additional fields | Linearization rule |
|---|---|---|
| `create` | `content_json`, `content_hash`; base exactly 0; no profile ID | Explicitly selected publish/keep-both only. Allocate a fresh server ID, content/object generation 1 and one account event. Append with a server-chosen order key; no local active change. |
| `update` | `profile_id`, base >=1, `content_json`, `content_hash` | Authenticated ownership + live current base required. Different exact bytes create a new immutable content generation and object/event revision. Identical bytes are a no-op receipt, no extra event. |
| `reorder` | `profile_id`, base >=1, `order_key` | Current live base required. Changed order increments object/event only; same order is a no-op. |
| `delete` | `profile_id`, base >=1 | Current live base required. Commit tombstone/event atomically. Subsequent use with the same mutation ID returns the original receipt; a new key on a tombstone yields gone, not a second deletion event. |

Scope idempotency to trusted `(issuer, environment, account)` plus mutation ID, **not session/family ID**. Concurrent same-key same-request attempts have one durable result. Same key with a different exact request fingerprint gives `idempotency_mismatch`, including after the head changes. A replay returns the originally committed record, not current head, without creating another ID/revision/event. Recheck account status/authorization on replay. Lost acknowledgement is retried with the original key/body; unreadable post-commit evidence gives `verification_pending`, never invented success. After an intent/receipt expires, require action/new reviewed intent; never blindly retry create with a new key.

Success is one validated record from the mutation's linearization point, correlated to the captured outbound request/context. It is not a proof of latest head after concurrent changes. AS06 must atomically commit object, immutable content, event and idempotency receipt and verify exact durable readback before emitting success; codec parsing alone is not this proof. Exhausted safe counters/quota fail without partial effects. AS06 chooses reviewed quotas/retention and persistent transaction implementation separately.

Fixed errors contain only `{schema, schema_version, result}`. Reserved results: `unavailable`, `invalid`, `requires_upgrade`, `conflict`, `gone`, `not_found`, `resync_required`, `idempotency_mismatch`, `intent_expired`, `verification_pending`, `quota_exceeded`. The bounded closed error parser returns only an immutable known-result enum/DTO. Unknown/future results, success-looking values, extra/private body/ID/account/profile/message/cursor fields, duplicates, bad integers/UTF-8 and byte overflow fail. This DTO is always NON-success: no accepted reference, cursor progression, implicit retry, state transition or private reflection. Tests feed every known error through read/page/mutation/record success parsers and require rejection. HTTP/authentication/error-response adapters remain AS02/AS06, not installed here.

## Bounded reads, consistent resync and no resurrection

Read requests are closed:

- `{mode:"changes"|"snapshot", cursor:null|opaque, limit:1...8}` plus schema/version;
- `{mode:"revision", profile_id, content_revision, content_hash}` plus schema/version.

`parseRead` returns an immutable typed page selector (changes/snapshot mode, exact nullable cursor, bounded limit) or revision selector (exact profile ID, content revision, content hash), not raw JSON or mode-only text. TS narrows by `mode`; Swift uses `ReadRequest.page`/`.revision`; Kotlin uses sealed `ReadRequest.Page`/`.Revision` with page-mode enum. Every positive read vector asserts case and all fields, including non-null cursors and the safe revision boundary. These selectors are not authenticated cursor/owner proof.

Cursors are `psc_` + 64 lowercase hex opaque references, not caller account/sequence selectors. Server lookup must authenticate and bind owner/mode/snapshot/high-watermark/position/expiry before reading content. Format validation is not cursor authentication. Source-only test bounds: maximum 100 live profiles, 15-minute consistent-view cursor lease and at most 256 retained change events before a cursor requires reset. These are reversible deterministic test choices, **not selected production quotas/retention/deletion policy**; missing real policy denies persistence.

A page has exactly `mode`, `snapshot_id` (`pss_` + 32 hex), `high_watermark`, `items`, `next_cursor`, `complete`, plus schema/version. `complete` is true exactly when next cursor is null; a nonfinal page cannot be empty. Snapshot pages contain only live rows in total order, with unique IDs. Change pages contain strictly increasing event sequences; multiple events for an ID are valid. No item can exceed the pinned high-watermark. All pages of one view retain the same owner/snapshot ID/high-watermark; a mismatch discards the tentative view and restarts. Per-page codecs cannot prove multi-page completeness; AS06/AS07 must enforce it.

Freeze a consistent live view at the snapshot high-watermark, including concurrent create/update/delete/reorder isolation. Cache pages idempotently but do not infer absence/delete mappings from an incomplete view. On completion reconcile absence as keep-local/unlink review, not silent native deletion or resurrection. Start subsequent changes after the same high-watermark. Expired/pruned/tampered/wrong-owner cursors give a fixed reset/error; build a fresh consistent snapshot and quarantine pending stale-base writes. Tombstone pruning never converts update into upsert. Content cannot recreate a retired ID; explicit republish requires a new selected create.

Revision reads return exact retained immutable content and its original validated reference/record, never "latest" substituted for a requested hash. Missing/expired revisions are unavailable, not reconstructed. Historical reads are not head events and cannot regress a local head or make a deleted object runnable. Config authority/policy/ownership still applies.

## Trusted account/environment binding — reviewed AS02 source; native binding still gated

**This lane does not implement account identity.** The profile-sync wire grammar intentionally has no caller account/environment field. A session/family ID identifies a revocable grant and can change across logins; it is not stable account identity. Names/email/native/cloud IDs/cursors/hashes are not account credentials.

Read-only reviewed coordinator integration `c29022c8216383444a2855659a7cd91fd66695d6` supplies the disabled synthetic AS02 `ConfigPrincipal` and `NativeSessionResponse` source choices:

```text
AS02 authenticated config authority -> ConfigPrincipal
  registered issuer + environment + config audience
  stable server-owned accountId from authoritative account/grant rows
  clientId + installationId + sessionId + current scopes/sessionGeneration
AS06 independently checks sync opt-in, selected intent and reviewed privacy policy
AS06 read/mutate(store, principal, parsed body) -> owner-scoped result
```

Issuer/environment come from reviewed service registration, never `PUBLIC_ORIGIN`, caller JSON, a supplied token claim or discovered provider. Account key comes from the authenticated server record, never an echoed selector. Every ID/cursor/event/content/receipt/store lookup and mutation is scoped to that principal and rechecks ownership/status at commit. AS02's issued-principal identity and authoritative commit recheck prove active account/grant/scopes, **not sync opt-in, privacy policy or selected-profile consent**; future adapters must independently recheck those. Wrong-owner IDs cannot reveal another head. Browser and native credentials retain AS01's distinct scope/Origin/CSRF rules; a codec caller supplying strings is not an authorized principal.

The reviewed token source response now delivers the server-owned stable `(issuer, environment, account_id)` plus `audience`, `client_id`, `installation_id`, session ID and `session_generation`. Namespace remains stable across refresh/new families for the same account; account replacement cannot inherit mappings. `session_generation` is a **nonnegative safe server integer**: actual authority initializes family generation **0**, increments on refresh, and `NativeAttempt` accepts `>=0`. The reviewed prose/brief saying positive was a coordinator wording error, not actual implementation semantics; this lane does not change auth/AS01 files. This server grant generation is distinct from the local account-switch generation and neither is standalone authority.

Source delivery is no longer an unspecified AS02 interface gate. However **AS03/AS04's bounded duplicate-safe native wire parser, exact registered issuer/environment/audience/client/installation/attempt/transport correlation, secure device-only storage and lifecycle binding remain mandatory unqualified gates**. The typed in-memory `NativeAttempt` is not that native proof. No sid/family/name/echoed-account fallback if binding is absent/mismatched; a bare profile response cannot supply it.

Only after the native binding gate is qualified:

1. The native auth adapter captures immutable verified namespace `(issuer, environment, account_id)` plus credential audience/client/installation/session/server generation and a separately monotonically changing local **account generation**. Store normal credentials/binding in the reviewed device-only secure namespace. The local generation is a cancellation/ownership fence, not a credential.
2. Persist mapping/outbox/cursor/candidate provenance under that owner tuple; map cloud ID to separately generated native ID. Capture owner/generation/expected outbound operation and immutable request bytes before sending with the matching configuration credential to the trusted service.
3. Bind results to the authenticated transport/request/session owner. On return recheck current binding/generation, expected request fingerprint, monotonic revisions/snapshot context, opt-in and local protection at the authoritative mutation commit. A parsed record alone is never enough to enqueue/apply/map under an account.
4. Switch/sign-out advances generation, stops sync, quarantines old owner's outbox/cache/mappings and rejects late responses. It does not copy credentials/grants/purchases, migrate pending writes, infer ownership from same-name profiles, or silently remove existing local profiles/independent schedules.

The `fence` fixtures use explicit synthetic owner/generation sentinels in a **test-only envelope**, not wire account authority or implemented secure queue/mapping reconciliation. Real native trusted-binding proof (AS03/AS04) and AS07 ownership/outbox/storage implementation remain unqualified.

## Selected publish/adopt/keep-both and conflicts

- **Publish selected local:** protected explicit disclosure consent + verified preservation source + validated exact content; create cloud ID only after verified receipt. Keep native ID/active/bindings/schedules/jobs unchanged. Lost ack must not allocate another object.
- **Adopt selected cloud:** explicit local action + fresh native ID. Persist execution block, nil bindings and disabled schedule state **before visibility**, with fetched content staged separately. Repeated adoption of an already mapped ID is a no-op mapping review, not another Add import. No global destination fallback.
- **Keep both:** retain the old candidate/local copy and create a genuinely new cloud identity with separately generated native identity if materialized. Same names are allowed/disambiguated by ID, never folded/merged.
- **Edit/edit or delete/edit:** mandatory CAS conflict, preserve both local pending body/base and remote immutable candidate. No implicit last-write-wins. User may discard pending intent, protectedly review/rebase a new exact update, keep-both with new IDs, or unlink/keep-local. Rebase uses a new mutation ID/current base and never edits a frozen queued request in place.
- **Edit/delete / remote deletion:** no auto-recreation or native last/active-profile deletion. Keep-local/unlink review preserves the last native profile and existing bound jobs. Explicit republish creates a new ID. Do not substitute another profile into scheduled/direct recovery.
- **Registry/grammar drift:** current registry hash requires every alias equal pinned evidence. Different valid source registry retains exact closed selections/aliases/extensions as `registry_review`; do not substitute native metrics or replace registry metadata in place. Future/unknown content fails and pauses publication/page apply/cursor advancement until a preserving upgraded reader/review is available.

## Preservation and execution boundary

Validated exact bytes are a fetched candidate, not accepted execution content. A separate local protected review must bind accepted revision/hash to locally validated metric meaning, concrete destination/credentials/grants, permissions, entitlement/background admission and execution scope. Remote execution-affecting edits cannot overwrite that accepted snapshot or clear a native identity-only import block. Active selection and enabled schedule/timezone/runtime history stay local. Frozen jobs/engine pins retain their original accepted settings/authority, never reload latest account content. Sign-in/sync/reorder/delete do not authorize health/request/upload/MCP operations.

A publish writer must read complete mapped source/foreign/unsupported preservation provenance using a throwing/verified loader, overlay only understood local edits, preserve unsupported foreign and inert destination/schedule meaning exactly, and validate the resulting bytes. Missing/corrupt/unreadable provenance quarantines publication; Apple's existing empty-on-read-failure map is not proof of foreign absence. A content parser cannot itself prove this IO provenance. The fixtures prove full codec round-trip/overlay bytes and specify quarantine; real sidecar/transaction writers are AS08/AS09 gates. No arbitrary unknown future fields are persisted as opaque extensions.

Local protection is rechecked at commit after asynchronous work; initial UI permission is insufficient. Existing local-only profiles, native IDs, destinations, permissions, purchases, app preferences, schedules/progress and running jobs are preserved. Accepted reference alone cannot grant export authority.

## Source APIs, fixtures and verification boundary

**Proposed typed codec seams only; local coordinator source review permits disabled synthetic consumer source use, not live/native authority.** Final-source conformance receipts, any unresolved parser/toolchain defects and component qualification are recorded in the AS05 report/TODO, not inferred from older runs. Read/error DTOs supply no authenticated owner binding, HTTP adapter, opt-in/privacy/selection proof, multi-page/outbox/reconciliation/store transaction or native apply. Native app/core/physical integration and consumer registration/freeze remain coordinator gates.

- TS: `ValidatedProfileSyncV1Content.parse`, `ValidatedProfileSyncV1Record.parse`, `parseProfileSyncV1Mutation`, `parseProfileSyncV1Read` -> discriminated `ProfileSyncV1Read`, `parseProfileSyncV1Error` -> `ProfileSyncV1FixedError`, `parseProfileSyncV1Page`, exact `profileSyncV1Hash`/`profileSyncV1MutationHash`; immutable content/reference and runtime brands. No routes/auth/storage.
- Swift: `ProfileSyncV1.Content.parse`, `.Record.parse`, `parseMutation`, `parseRead` -> `ReadRequest`, `parseError` -> `FixedError`, `parsePage`, `contentHash`/`mutationHash`. Real v2 codec plus closed field/security/registry checks; no core build required for the host runner.
- Kotlin: `ProfileSyncV1.parseContent`, `parseRecord`, `parseMutation`, `parseRead` -> sealed `ReadRequest`, `parseError` -> `FixedError`, `parsePage`, `contentHash`/`mutationHash`. Real v2 codec and serialization DTOs; host runner injects **byte-pinned registry rows**, never a success validator. Actual core/Android registry adapter remains unverified by that runner.
- Python: `validator.py`, `test_contract.py`, deterministic schema/vector builders and full-content/reference validation.

`fixtures/content-vectors.json` covers Apple policies, Android compatibility/raw, current/changed registry, Unicode and foreign unchanged/local-edit overlays. `parser-cases.json` covers malformed/duplicate/escaped/NFC-equivalent keys, UTF-8/BOM/surrogates, byte/depth/text/map bounds, prohibited native/health/secret/runtime fields and strings, URI/path safety, strict revisions/versions, registry/alias/schedule contradictions, hash references, mutations, typed page/revision reads, all known fixed errors and malformed/private/success-shaped errors, pages and the explicit edge-Unicode name subset. `scenarios.json` covers publish/lost ack/replay, conflicts, reorder, resync/tombstones, account/env/generation fences, same names, adopt/keep-both, protection, preservation and candidate-vs-accepted snapshots.

Scenario predicates in the runners are explicitly **test-only source oracles**, not production server CAS/idempotency/storage, AS07 reconciliation or native transaction/IO/physical evidence. Parsing exercises actual codec code before those predicates; passing them does not supply missing runtime authority/durability/race proof.

Cheap checks:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 packages/contracts/profile-sync/v1/test_contract.py
PYTHONDONTWRITEBYTECODE=1 python3 packages/contracts/validate.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s packages/contracts -p test_validate_shared_setup.py
```

Guarded standalone checks (Node 24 explicitly; use this fleet's `with-heavy-slot.sh` prefix, never bypass exit 75):

```bash
node --experimental-transform-types packages/contracts/profile-sync/v1/run-typescript.mjs
bash packages/contracts/profile-sync/v1/run-swift.sh
bash packages/contracts/profile-sync/v1/run-kotlin.sh
```

Native runners use owned `.build` or `PROFILE_SYNC_BUILD_DIR` scratch. Kotlin reads existing explicitly versioned cached compiler/Trove4j/serialization/JUnit jars only; no Gradle, installation or cache copy. Node's runtime transformation/conformance is not full Cloud TypeScript/Vitest/Worker qualification. Full Xcode/Gradle/core builds require coordinator admission. Exact run receipts, failures, resource-blocked post-edit checks and outstanding gates are in the AS05 TODO/report, not implied by runnable scripts.

Coordinator integrated repair `1b5d4c769094563bf98d3619a728eeb32107602c` by `6d8e0f17007dd12aeaa12d8610791fe6bb93db60`, qualified the combined source codecs, and centrally registered deferred manifest records, planned capabilities and Cloud source-check triggers. The integrated Cloud strict compiler caught an optional indexed `formats` input; its array-check helper now accepts undefined at the validation boundary and still rejects it, with a regression test. This is not consumer canonicalization or native app/core qualification. The lane itself made no shared registration changes; public schema fixtures, lockfiles, native build/project hooks, exporter/daily/API/direct/core/CLI/website/Obsidian bytes remain unchanged. Affected future consumers are Cloud account config, Apple/Android sync/apply adapters and dashboard; CLI/local MCP/direct/website/provider/store paths receive no new authority. Real privacy/key/retention/deletion/region policy, stable native account binding, durable service/reconciliation, local execution-review transaction, physical/accessibility and product/rollout gates remain pending.
