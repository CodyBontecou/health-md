# AS07 bounded Python SOURCE kernel

**Partial synthetic-only SOURCE, not public/wire grammar, production reconciliation,
authentication, native apply or durable storage.** Governing:
[AS05](../contract.md),
[source design](../../../../../docs/architecture/account-profile-sync-source-design.md),
[unification policy](../../../../../docs/architecture/cross-platform-unification-policy.md).
No codec/manifest/version/capability/consumer bytes change. TypeScript/Swift/Kotlin,
Cloud/app/core/CLI/website/Obsidian and native/physical consumers remain
planned/unimplemented or unqualified by this slice.

## Interface and transitions

`Kernel()` is unavailable: **no installed ports, journal reads, parser calls or
profile transfer**. `Kernel.synthetic(context, journal, codec_path=None)` explicitly
installs the actual AS05 Python parser and an in-memory journal. `Context` permits
only fixed reserved-domain/test sentinels and a nonnegative safe local generation;
it is not a configuration principal, credential, consent, opt-in or privacy approval.
A raw future auth claim cannot construct this factory's context type.

Results are fixed codes, without names/bodies/owner IDs in errors/descriptions.
Only `next_request()` includes an immutable sensitive request. Explicit synthetic
state/request access is not safe logging, telemetry or serialization.

- `local(context, native_id, exact_content_bytes)` seeds a **pre-existing synthetic
  portable copy/accepted AS05 marker**, not approved native execution or new approval.
- `observe(context, exact_record_bytes)` parses one supplied synthetic head event.
  Immutable candidates retain exact outer/content bytes, hash and review flags.
  Old/repeated events cannot regress heads; contradictory references fail closed.
  Live order is ascending `(order_key, ASCII profile_id)`; names are not identities.
- `select(context, choice, native_id, payload, conflict_id=None)` permits explicit
  `publish`, `adopt`, `edit`, `delete`, `reorder`, `keep_both`. Adopt takes an observed
  cloud ID/fresh supplied native sentinel and stages a relation/review intent only:
  no native row/accepted marker or repeated duplication. Other payloads are exact
  AS05 mutation bytes, never reconstructed DTOs. Publish matches the seeded copy;
  edit/delete need a local copy/live link/head/exact base. Keep-both preserves pending
  conflict bytes/remote candidate and requires new selected create/key/distinct
  supplied native ID, never targeting a retired cloud ID.
- `next_request()` inspects, never sends, the oldest eligible captured request.
  Lost ack reinspection retains exact bytes/key/domain hash/base/owner generation.
  Conflicted/quarantined/acknowledged work is retained but ineligible; no transparent
  create/rebase/fresh retry key.
- `acknowledge(context, key, request_hash, exact_record_bytes)` correlates captured
  context/hash/operation/base/content/revisions. Create maps a new response-shaped
  ID only after exact readback; update no-op retains content revision; delete stages
  keep-local/unlink review. Bad owner/hash/content/reference quarantines work, not
  copies. Parsed receipts prove neither server issuance/ownership/auth nor latest head.
- `switch(next_context)` advances generation/quarantines work without rewriting
  owner/body/base/copies/accepted markers. Its immediate local fence stops old work
  even if quota/fault prevents recording the switch.
- `view()` is the verified immutable view; `verify()` compares exact readback, never
  trusting `apply()` return alone.

Candidates, dirty pending bytes/base and accepted markers are separate. Edit/edit,
edit/delete and delete/edit preserve both sides, never last-write-wins. No accepted-
content rewrite, name normalization, foreign-byte change, bundle import or frozen-job
read. **No network/clock/random/browser/health/provider/native-binding/destination/
schedule/purchase/jobs ports**: a source-library property, not app-wide cold/foreground
zero-call evidence.

## Explicit outbound reorder: metadata only

Reorder requires a live cloud ID explicitly linked to the supplied native sentinel,
an exact current owner/generation and an actual AS05-validated reorder body/base/
order key. An adopted portable relation can reorder without a local copy; it still
creates no native row or acceptance. Wrong operation/ID/base, unlinked/deleted or
pending/conflicted state, malformed types and capacity overflow refuse before
journal apply, preserving existing work. The frozen parser's unhashable malformed
operation `TypeError` is caught as fixed `invalid` at the mutation caller boundary;
no codec/wire rule changes.

The frozen outbox captures `desired_order`, exact base content/reference, original
body/key/hash/base/context. Reinspection/retry cannot reconstruct bytes; same-key
byte mismatch refuses even if a semantically equivalent JSON representation was
supplied. Selection itself cannot reorder heads or alter accepted/local/foreign
content. No name merging, ID allocation, bootstrap or active selection occurs.

A correlated receipt must retain profile ID, exact base content bytes/hash and
content revision. Changed order requires precisely the requested order, object
revision base+1 and a later event. Same-order no-op requires the original object,
event, content and order; it adds no candidate revision. Actual AS05 lexical/safe
integer checks precede receipt matching: no overflow/wrap can succeed. A bounded
intent at exhausted counters is not server capacity proof; an overflowing receipt
is rejected/quarantined, not synthesized as success. Request/receipt journal faults
use the same uncertain/fenced readback rules below. Conflicts and owner switches
cannot silently rebase, unquarantine or transfer the captured intent.

## Partition consistency versus generation eligibility

Retirement/object/content/event constraints belong to `(issuer, environment, account)`,
not cancellation generation. `observe` checks retained partition candidates/newest
known head even without a current staged head. Retired IDs cannot stage live content
or immutable references different bytes. Older exact records/exact newest replay
return `unchanged`; contradictions require action without writes; valid forward
current-generation events can stage.

`State.head`/`ordered_heads` expose only staged exact-generation rows. Partition
knowledge restricts input, not visibility/mapping/upload/execution/auth authority.
Rejection/ignoring can leave the new head absent while the old head/tombstone,
context/raw bytes, accepted markers and outbox provenance survive unchanged.
Forward candidates cannot unquarantine work/mappings. Other partitions independently
permit identical IDs/references with equal/different valid bytes; return consults
only that owner's head, not another's higher revision. No resync or cached-copy
transfer occurs.

Historical `97efea8348d14e88173d443f92c58f26e14b671c` 17-test success did **not**
establish these constraints: three independent actual-source probes subsequently
failed. Repair `503d01a0450e23c861b792303d11d392ed1819b0` has separate red/green
receipts. Original reports/logs remain historical, not new integration qualification.

## Journal faults and restart limits

`journal.py` supplies `read()` / `apply(expected_record, owner, proposed_state)` to
both memory/fault adapters. A real `Lock` serializes expected-record comparison,
owner fencing and state mutation. The kernel accepts only exact intended readback.
Two-kernel tests are **deterministically interleaved actual CAS**, not thread stress,
OS synchronization or durability.

- `no_op`: **state-apply no-op WITH successful proposal retention**, not whole-
  journal-write loss, process/OS crash. Prior state and exact desired intent remain;
  the kernel stays uncertain.
- `partial`: applies proposed locals/candidates/links/history but retains prior
  outbox, alongside original/desired states. Only the verified prior view is exposed.
- `lost_response`: commits then throws. Readable exact readback can genuinely verify
  that in-memory commit; without it success is not guessed.
- `unreadable`: commits then reads fail. Intent survives in original caller/journal,
  with prior visible view and no dispatch until explicit test read-unblock and
  exact verification.
- `stale_owner`: changes the sentinel fence at the exclusive mutation point and
  retains the unapplied proposal. Old work stays fenced.

No rollback/compensating write/automatic repair/discard. Snapshot restart uses only
an exact read-returned in-memory `Record` through the same seam, retaining queued/
acknowledged bytes/owner tags. **Unresolved pending snapshots remain uncertain/fenced**,
never promoted. A losing CAS proposal stays only with that caller, not the winner's
journal: no durability for uncommitted input. Unreadable restart cannot infer absent
copies/success. No JSON/file/SQL/OS crash recovery, private durable journal, encryption
or privacy/deletion adapter.

## Bounds (SOURCE ONLY)

Reversible test constants, not product quotas or retention promises:

- 8 local copies, 8 links, 8 owner/generation-tagged cloud identities;
- 8 total outbox entries, including acknowledged/conflicted/quarantined history;
- 32 immutable observed revisions and 32 action/transaction steps;
- 32,768 bytes per captured input; 131,072 conservative logical state bytes;
- at most three such states plus 4,096 metadata bytes per retained fault envelope.

Accounting charges exact inline payloads/references even when immutable Python
objects share memory; it is not heap measurement. Exhaustion returns
`quota_exceeded`, preserves prior/pending bytes and never prunes work to fit.
Unreadable/failed readback returns `verification_pending`; detected owner change
remains `fenced`. These small budgets stop long-lived operation. No expiry,
compaction or production retention/deletion choice exists.

## Remaining omissions and conservative behavior

- No multipage/snapshot completeness, cursor ownership/reset, bootstrap full-resync
  or absence-driven unlink. A page passed to `observe` fails the actual record
  parser; `complete` shape cannot establish a complete view.
- No historical revision-read correlation, general arrival-order reconciliation,
  automatic/explicit rebase, pending discard, unlink execution or conflict-resolution
  completion. Observed/acknowledged reorder is portable metadata, not native active
  selection or accepted-content change.
- **A create acknowledgement whose ID was already observed is conservatively
  quarantined even for legitimate head-before-lost-ack arrival.** Cached content
  cannot establish mapping/receipt. Outer-record duplicate checks use exact bytes;
  representation differences require action. This is not complete server/transport
  receipt reconciliation.
- No generated native/cloud IDs, real owner/auth/session binding, consent/opt-in,
  verified sidecar/preservation IO, foreign edit overlay writer, commit-time local
  protection admission or privacy policy. Synthetic byte capture cannot prove a
  real native loader preserved unsupported intent.
- No native-visible apply/block/binding transaction, accepted-revision approval,
  activation, nil-destination fallback handling, schedule/job/frozen-work reload,
  last-profile enforcement, secure storage or independently bound execution.
  Existing native/app state is absent, not simulated as done.
- No OS storage/key/retention/erasure, SQL/server idempotency, real network
  acknowledgements/concurrency or production durability. Named issuer, product,
  security/privacy/operations/mobile/physical/accessibility/rollout gates remain
  open. Language/native/app/storage consumers remain unimplemented.

## Light verification

Standard-library only, no dependencies/build artifacts or filesystem persistence:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  packages/contracts/profile-sync/v1/reconciliation-source/test_reconciliation.py
```

For sparse SOURCE without the shared Rust registry, explicitly configure **tests
only** to read actual matching frozen complete AS05 source:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  packages/contracts/profile-sync/v1/reconciliation-source/test_reconciliation.py \
  --codec-path "$FROZEN_SOURCE_ROOT/packages/contracts/profile-sync/v1/validator.py"
```

`AS07_CODEC_PATH` is equivalent. No host/scratch absolute path is committed. The
loader requires identical local/frozen validator bytes; real dependencies are read
in place, never copied, mocked, modified or replaced by permissive validation.
Source identity is not trust or native/heavy admission. Whole shared verifiers need
complete inputs and separate coordinator verification, not this sparse receipt.

36 tests retain all original24 invariants, except the intentionally obsolete
reorder-unavailable assertion/comment now tests actual reorder/fields. Original
observed-order/content assertions/page-reset refusals remain. The 15 byte-unchanged
**independently authored** traces run twice: literal outcomes/state/history/calls,
fixture hash/input reproduction, real AS05 calls, exact content/request/base/owner
bytes, candidates vs accepted markers, correlated receipts, actual CAS/readback/
faults, restart fencing and real profile/outbox/history/byte limits. Seven partition
tests retain genuine regression reds and forward/isolation/return positives.

Twelve new public-interface tests add changed/no-op/tied/zero/safe-max reorder,
counter overflow, exact retry/key mismatch, malformed requests/receipts/reference
drift, scope/generation/dirty/conflict/link fences, portable adoption, enqueue/receipt
faults, verified/pending snapshot restart and retained-outbox/CAS bounds. Helpers
construct inputs, not output oracles; expected fields/statuses are independent,
not generated goldens or AS05 scenario predicates. Genuine absent-feature RED,
malformed-operation errors, quota-test expectation failures and working-source
budget assertion remain external. Separate handoffs record commands/committed
scope/hashes/omitted gates; tests do not qualify coordinator integration, native/auth/
privacy or OS durability.
