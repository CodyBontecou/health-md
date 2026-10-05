# AS07 bounded Python SOURCE kernel

**Partial, synthetic-only reference implementation. Not public/wire grammar,
production reconciliation, authentication, native apply or durable storage.**
The [AS05 proposed contract](../contract.md),
[source design](../../../../../docs/architecture/account-profile-sync-source-design.md)
and [unification policy](../../../../../docs/architecture/cross-platform-unification-policy.md)
remain governing. No existing codec, manifest, version, capability or consumer
bytes change. TypeScript/Swift/Kotlin, Cloud, app/core/CLI/website/Obsidian and
native/physical qualification remain planned/unimplemented by this slice.

## Interface and implemented transitions

`model.py` exposes `Kernel()`, which is unavailable with **no installed ports,
journal reads, parser calls or profile transfer**. `Kernel.synthetic(context,
journal, codec_path=None)` explicitly installs the actual AS05 Python parser and
an in-memory journal. `Context` accepts only the fixed reserved-domain/test
sentinels in source plus a nonnegative safe local generation. It is not a
configuration principal, credential, consent, sync opt-in or privacy approval.
A raw future auth claim cannot construct this factory's context type.

Operations return fixed `Result.code` strings; only `next_request()` can include
an immutable sensitive request. No names, bodies or owner IDs are included in
errors/descriptions. State/request views are explicit synthetic test data access,
not a safe logging/telemetry or serialization interface.

- `local(context, native_id, exact_content_bytes)` seeds a **pre-existing synthetic
  portable user copy and accepted marker**. The marker is immutable AS05 content,
  not an actual approved/native execution snapshot or a new approval action.
- `observe(context, exact_record_bytes)` parses one explicitly supplied synthetic
  head event into an immutable candidate. Old/repeated events do not regress the
  head; conflicting immutable references fail closed. Candidates retain exact
  outer record bytes and AS05 `ValidatedContent.raw`/hash/review flags. Live heads
  have deterministic `(order_key, ASCII profile_id)` order; names are not keys.
- `select(context, choice, native_id, payload, conflict_id=None)` admits only
  explicit `publish`, `adopt`, `edit`, `delete`, `keep_both` source intents.
  `adopt` payload is an already observed cloud ID; it only stages a portable
  relation/review intent with a fresh supplied sentinel native ID. It creates no
  native-visible row or accepted marker. Repeated adoption does not duplicate it.
  Other payloads are **original AS05 mutation bytes**, not reconstructed DTOs.
  Publish must match the exact seeded portable local copy. Edit/delete require a
  live linked head and exact base. Keep-both preserves the conflicting pending
  body and remote candidate, requires a new explicit create/key and distinct
  supplied native ID, and never targets a retired cloud ID.
- `next_request()` returns the oldest eligible immutable captured request, never
  sends it. Lost network acknowledgement is represented by inspecting it again:
  identical original bytes, mutation ID, domain-separated request hash, base and
  owner generation. Conflicted/quarantined/acknowledged entries are retained but
  not emitted. There is no transparent create, rebase or fresh retry key.
- `acknowledge(context, key, request_hash, exact_record_bytes)` correlates source
  context/hash/operation/base/exact content and expected revisions. Create maps a
  new server-response-shaped cloud ID only after verified journal readback;
  update no-op receipts retain their immutable content revision; delete emits
  keep-local/unlink review. Wrong owner/hash/content or contradictory reference
  quarantines pending work, never native/user copies. A parsed response is **not
  proof of real server issuance, ownership, authentication or latest head**.
- `switch(next_context)` advances the local generation and quarantines old work
  without changing its original owner/body/base. Local copies and accepted
  markers remain unchanged. Even when quota/fault prevents recording the switch,
  the calling kernel immediately stops old work through its local fence.
- `view()` exposes the last verified immutable state. `verify()` compares actual
  journal readback, never assumes that `apply()` returning means success.

Fetched candidates, dirty pending bytes/base and seeded accepted markers remain
separate. Edit/edit, edit/delete and delete/edit preserve pending and remote work
without last-write-wins. No operation rewrites accepted content, normalizes names,
changes foreign bytes, imports Shared Setup bundles or reads frozen jobs.
There are **no** network, clock, random, browser, health/provider, native binding,
destination, schedule, purchase or jobs ports. This absence is a library/source
property, not app-wide cold/foreground zero-call evidence.

## Journal seam, faults and restart limits

`journal.py` defines one `read()` / `apply(expected_record, owner, proposed_state)`
interface, used by both `MemoryJournal` and `FaultJournal`. An actual `Lock`
serializes expected-record comparison, owner fencing and state mutation. The
kernel accepts a transition only after the exact intended record is read back.
The tests include a **deterministically interleaved two-kernel CAS winner/loser**;
this is not concurrent-thread stress, OS synchronization or storage durability.

- `no_op` is **state-apply no-op WITH successful proposal retention**, not loss of
  the entire journal write, process crash or OS crash. The original state and
  exact desired intent remain in the journal; the kernel stays uncertain.
- `partial` writes actual proposed locals/candidates/links/history but retains the
  prior outbox, alongside original and exact desired states. The kernel exposes
  only the verified prior view, never that partial state as success.
- `lost_response` commits and throws. A readable exact readback can genuinely
  verify that in-memory commit; without that evidence success is not guessed.
- `unreadable` commits then makes reads fail. Intent stays in the original kernel
  and committed journal, with prior visible view and no dispatch, until an
  explicit test read-unblock permits exact verification.
- `stale_owner` changes the sentinel journal fence at the actual exclusive
  mutation point and retains the unapplied proposal. Old work stays fenced.

No rollback, compensating write, automatic repair or discard occurs. An exact
in-memory `Record` returned by `read()` can initialize another adapter through
that same interface. Queued/acknowledged bytes and owner tags survive that source
snapshot restart. **Unresolved `pending` records stay verification-pending/fenced
on restart**, not silently promoted. A rejected competing CAS proposal is retained
only by the losing caller, not the winning journal; there is no durability promise
for uncommitted caller input. Restart while readback is unavailable cannot infer
an absent user copy or committed success. No JSON/file/SQL/OS crash recovery,
persistence, privacy/encryption/deletion adapter or native durable journal exists.

## Bounds (SOURCE ONLY)

Constants are reversible source test choices, not product quotas/retention:
8 local copies, 8 links, 8 owner/generation-tagged cloud identities; 8 total outbox
entries including historical/conflicted/quarantined entries; 32 immutable observed
revisions and 32 action/transaction steps; 32,768 bytes per captured input;
131,072 conservative logical state bytes; at most three such states plus 4,096
metadata bytes in a retained journal fault envelope. Logical accounting charges
all exact inline payloads/references even when Python immutable objects share
memory; it is not a Python heap measurement.

Exhaustion refuses the new transition with `quota_exceeded`, preserves prior and
pending bytes, and never prunes history/outbox/user work to fit. A failed/unreadable
readback returns `verification_pending`; a detected owner change remains `fenced`.
These small budgets intentionally stop long-lived operation. No expiry/compaction,
production quota or retention/deletion claim is made.

## Exact omissions / conservative behavior

- No multipage/snapshot completeness, cursor ownership/reset, bootstrap full-resync
  or absence-driven unlink. A page passed to `observe` is rejected by the actual
  record parser; `complete` shape cannot imply a complete view.
- No outbound reorder, historical revision-read correlation, general arrival-order
  reconciliation, automatic/explicit rebase, pending discard, unlink execution or
  conflict-resolution completion. An observed metadata reorder is only a staged
  candidate; it never changes native active selection or accepted content.
- **A create acknowledgement whose ID was already observed is conservatively
  quarantined even for legitimate head-before-lost-ack arrival.** Identical cached
  content cannot establish the mapping/receipt. Likewise outer-record duplicates
  use exact bytes; representation differences require action. This kernel is not
  a complete server/transport receipt-correlation solution.
- No generating native/cloud IDs, real owner/auth/session binding, consent/opt-in,
  complete sidecar/preservation IO provenance, foreign edit overlay writer, local
  protection admission or privacy policy. Synthetic exact-byte capture is not
  proof that a real native loader preserved all unsupported intent.
- No native-visible apply/block/binding transaction, accepted-revision approval,
  activation, nil-destination fallback handling, schedule/job/frozen-work reload,
  last-profile enforcement, secure storage or independently bound execution.
  Existing native/app state is absent from this interface, not simulated as done.
- No OS journal, encryption/key/retention/erasure, SQL/server idempotency, actual
  network acknowledgements/concurrency or production durability. Named issuer,
  product/security/privacy/operations/mobile/physical/accessibility/rollout gates
  remain open. All language/native/app/storage consumers remain unimplemented.

## Light verification

Standard-library only, no dependencies/build artifacts or filesystem persistence:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  packages/contracts/profile-sync/v1/reconciliation-source/test_reconciliation.py
```

For a sparse SOURCE checkout missing the shared Rust registry, explicitly point
**tests only** at the actual matching frozen complete AS05 source:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  packages/contracts/profile-sync/v1/reconciliation-source/test_reconciliation.py \
  --codec-path "$FROZEN_SOURCE_ROOT/packages/contracts/profile-sync/v1/validator.py"
```

`AS07_CODEC_PATH` is the equivalent explicit test setting. No host/scratch absolute
path is committed. The loader requires identical local/frozen `validator.py`
bytes; its real dependencies are read in place, never copied, mocked, modified or
replaced with permissive validation. This check is source identity, not trust or
heavy/native admission. Whole-repository shared verifiers require complete inputs
and are separate coordinator gates, not claimed from this sparse lane.

17 source tests run 15 small **independently specified** positive/negative/fault
traces twice, checking literal expected statuses/state/history/journal call counts,
fixture SHA-256, deterministic input reproduction, actual AS05 parser calls,
returned exact content/request/base/owner bytes, immutable candidate vs accepted
markers, correlated receipts, real CAS/readback faults, restart fencing and actual
profile/outbox/history/byte limits. Same-name/tied-order and metadata-reorder tests
field-assert actual ordered IDs/order keys/content revisions/hashes/raw bytes and
contexts against independently authored expectations. Fixtures contain only
synthetic AS05 content. They are not copied/renamed AS05 scenario predicates or
implementation-generated output goldens. Exact commands, all genuine failures,
committed scope/hashes and remaining gates belong in the external lane handoff.
