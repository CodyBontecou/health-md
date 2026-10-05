# AS07 bounded Python SOURCE kernel

**Partial synthetic SOURCE, not public/wire grammar/production reconciliation/auth/
native apply/durable storage.** Governing [AS05](../contract.md),
[source design](../../../../../docs/architecture/account-profile-sync-source-design.md),
[unification policy](../../../../../docs/architecture/cross-platform-unification-policy.md).
Codec/manifest/version/capability/consumer bytes unchanged; TS/Swift/Kotlin/Cloud/
app/core/CLI/website/Obsidian/native/physical remain planned/unimplemented/unqualified.

## Interface and transitions

`Kernel()`: unavailable; zero ports/journal reads/parser calls/profile transfer.
`Kernel.synthetic(context, journal, codec_path=None)`: explicit real AS05 Python
parser/memory journal. `Context`: fixed test/reserved-domain sentinels/nonnegative safe local
generation only; no raw future auth claim/config principal/credential/consent/
opt-in/privacy approval. Fixed errors omit names/bodies/owner IDs;
descriptions too. Only next_request returns sensitive immutable request; state/
request access != safe logging/telemetry/serialization.

- `local(context, native_id, exact_content_bytes)`: pre-existing synthetic portable
  copy/accepted AS05 marker, not native execution/new approval.
- `observe(context, exact_record_bytes)`: one synthetic head, immutable outer/content
  bytes/hash/review flags; no old/repeated regression, contradictions fail closed.
  Ascending `(order_key, ASCII profile_id)`; names are not identities.
- `select(context, choice, native_id, payload, conflict_id=None)`: explicit publish,
  adopt, edit, delete, reorder, keep_both. Adopt: observed cloud ID/fresh supplied
  native sentinel/relation-review only, no native row/accepted marker/duplication.
  Others: exact AS05 bytes, no DTO rebuild. Publish matches seed; edit/delete need
  local copy/live link/head/exact base. Keep-both preserves conflict/remote bytes;
  new selected create/key/distinct supplied native ID, never retired cloud ID.
- `next_request()`: oldest eligible capture, never send; lost-ack retry keeps exact
  bytes/key/domain hash/base/owner generation. Retained conflict/quarantined/acked
  work ineligible; no transparent create/rebase/new key.
- `acknowledge(context, key, request_hash, exact_record_bytes)`: correlate captured
  context/hash/op/base/content/revisions. Create maps new response-shaped ID after
  exact readback; update no-op keeps content revision; delete: keep-local/unlink
  review. Bad owner/hash/content/reference quarantines work, not copies. Parsed
  receipt != server issuance/ownership/auth/latest head.
- `switch(next_context)`: generation advance/quarantine; owner/body/base/copies/
  accepted unchanged, immediate local fence even if quota/fault prevents recording.
- `view()`: verified immutable view; `verify()`: exact readback, never apply-return trust.

Candidates/dirty bytes+base/accepted markers separate. Edit/edit, edit/delete,
delete/edit preserve both sides, no last-write-wins. No accepted rewrite/name
normalization/foreign-byte change/bundle import/frozen-job read. No network/clock/
random/browser/health/provider/native-binding/destination/schedule/purchase/jobs
ports: SOURCE-only, not app-wide cold/foreground zero-call evidence.

## Explicit outbound reorder: metadata only

Live explicitly linked cloud ID/native sentinel/current owner-generation/real AS05
body-base-order required. Adopted relation may reorder without local copy, not
native row/acceptance. Wrong op/ID/base/unlinked/deleted/pending/conflict/malformed/
overflow: preserve work/refuse before apply. Unhashable-operation `TypeError`:
caller fixed `invalid`, frozen codec/wire unchanged.

Frozen outbox: `desired_order`, exact base content/reference, original body/key/
hash/base/context. Retry/reinspection never rebuilds bytes; same-key byte mismatch
refuses even equivalent JSON. Selection cannot reorder heads/change accepted/local/
foreign content/merge names/allocate IDs/bootstrap/select active.

Receipt retains ID/exact base bytes/hash/content revision. Changed order: requested
order/object base+1/later event. Same-order no-op: original object/event/content/
order, no candidate revision. Actual AS05 lexical/safe-integer checks precede
matching; no overflow/wrap. Bounded intent at exhausted counters != server capacity;
overflowing receipt rejected/quarantined, never synthetic success. Request/receipt
faults use uncertain/fenced readback below; conflicts/switch cannot silently rebase/
unquarantine/transfer intent.

## Partition consistency versus generation eligibility

Retirement/object/content/event constraints: `(issuer, environment, account)`, not
generation. `observe` checks retained newest partition head/candidates even without
current staged head. No live retired IDs/reference byte rewrites. Older exact/
newest exact replay: `unchanged`; contradictions: action/no writes; valid forward
current-generation may stage. `State.head`/`ordered_heads`: staged exact-generation
only. Knowledge restricts input, not visibility/mapping/upload/execution/auth.
Rejection/ignore may leave new head absent while old head/tombstone/context/raw/
accepted/outbox provenance stays unchanged. Forward cannot unquarantine work/maps.
Independent partitions permit same IDs/references/equal or different valid bytes;
return uses own head, not another's higher revision. No resync/cached-copy transfer.

17-test `97efea8348d14e88173d443f92c58f26e14b671c` did not prove this: three later
independent actual-source probes failed. `503d01a0450e23c861b792303d11d392ed1819b0`
repair has separate RED/GREEN; old reports/logs historical, not new integration proof.

## Journal faults and restart limits

`journal.py`: memory/fault read()/apply(expected_record, owner, proposed_state).
Real `Lock` serializes comparison/fencing/mutation; accept exact intended readback
only. Two-kernel actual deterministic interleaved CAS != thread stress/OS sync/durability.

- `no_op`: state-apply no-op WITH successful proposal retention (prior state/exact
  desired intent/uncertainty), not whole-write loss/process/OS crash.
- `partial`: proposed locals/candidates/links/history/prior outbox; original/desired
  states retained, only verified prior view visible.
- `lost_response`: commit then throw; readable exact readback verifies memory
  commit, otherwise never guess success.
- `unreadable`: commit/failed reads; intent in original caller/journal, prior view,
  no dispatch until explicit test read-unblock/exact verification.
- `stale_owner`: exclusive mutation changes sentinel fence/retains unapplied
  proposal; old work fenced.

No rollback/compensating write/automatic repair/discard. Same-seam read-returned
memory `Record` restart retains queued/acked bytes/owner; pending stays uncertain/
fenced, never promoted. CAS loser proposal only with caller, not winner's journal;
uncommitted input not durable. Unreadable restart proves no absence/success.
No JSON/file/SQL/OS recovery/private durable journal/encryption/privacy/deletion.

## Bounds (SOURCE ONLY)

Reversible SOURCE constants, not product quotas/retention promises:
8 locals/8 links/8 owner-generation cloud identities; 8 retained outbox entries
(acked/conflicted/quarantined included); 32 immutable observed revisions/32 action-transaction
steps; 32,768 input bytes/131,072 conservative logical state bytes; fault envelope
<=three states+4,096 metadata bytes. Exact inline payloads/references charged even
when immutable objects share memory: not heap measurement. Exhaustion:
`quota_exceeded`, preserve prior/pending bytes, never prune. Unreadable/failed
readback: `verification_pending`; detected owner change: `fenced`. Budgets stop
long-lived operation; no expiry/compaction/production retention/deletion choice.
Pending inspection after readiness/verified readback/lookup: `quota_exceeded`, no
Request at full steps or if canonical quarantine cannot fit; no apply/reservation/
state change. No pending: `requires_action`. This minimum-denial fence does not
prove capacity for all successful receipts/new references or dispatch/server policy.

## Remaining omissions and conservative behavior

- No multipage/snapshot completeness/cursor ownership-reset/bootstrap full-resync/
  absence unlink. Page to `observe`: actual record-parser failure; `complete` !=
  complete view.
- No historical revision-read correlation/general arrival ordering/automatic or
  explicit rebase/pending discard/unlink execution/full conflict resolution.
  Observed/acked reorder is portable metadata, not native active/accepted change.
- **Already-observed-ID create ack is conservatively quarantined, including genuine
  head-before-lost-ack.** Cache cannot prove mapping/receipt. Exact outer-byte
  duplicates only; representation differences require action, not complete
  server/transport receipt reconciliation.
- No generated native/cloud IDs/real owner-auth-session binding/consent/opt-in/
  verified sidecar-preservation IO/foreign edit overlay writer/commit-time local
  protection/privacy policy. Byte capture != native-loader unsupported-intent proof.
- No native-visible apply/block/binding transaction/accepted-revision approval/
  activation/nil-destination fallback/schedule-job-frozen-work reload/last-profile/
  secure storage/independently bound execution. Native/app state absent, not done.
- No OS storage/key/retention/erasure/SQL-server idempotency/real network ack-
  concurrency/production durability. Named issuer/product/security/privacy/
  operations/mobile/physical/accessibility/rollout gates open; language/native/app/
  storage consumers unimplemented.

## Light verification

Stdlib only; no dependencies/build artifacts/filesystem persistence:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  packages/contracts/profile-sync/v1/reconciliation-source/test_reconciliation.py
```

Sparse registry absent; tests only read actual matching frozen complete AS05:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  packages/contracts/profile-sync/v1/reconciliation-source/test_reconciliation.py \
  --codec-path "$FROZEN_SOURCE_ROOT/packages/contracts/profile-sync/v1/validator.py"
```

`AS07_CODEC_PATH` equivalent; no committed host/scratch paths. Identical local/
frozen validator, real in-place dependencies; no copy/mock/change/permissive
substitute. Identity != trust/native/heavy admission; whole shared gates need
complete inputs/separate coordinator proof.

38 tests: all original24 invariants (only obsolete reorder-absence assertion/comment
replaced with reorder/field checks); original observed-order/content/page-reset
checks retained. 15 unchanged independently authored traces twice: literal outcomes/
state/history/calls, fixture hash/reproduction, actual AS05, exact content/request/
base/owner, candidate vs accepted, receipts/CAS/readback/faults/restart/profile/
outbox/history/byte limits. Seven partition tests: genuine REDs/forward/isolation/
return. Twelve reorder tests: changed/no-op/tie/zero/safe-max/overflow/retry/key
mismatch/malformed request+receipt/reference drift/scope/generation/dirty/conflict/
link/adoption/enqueue+receipt faults/verified+pending restart/outbox+CAS. Step/byte
inspection: below-capacity controls/trusted read-returned restart.

Input helpers != output oracles: independent fields/statuses, no generated goldens/
AS05 scenario predicates. Genuine feature REDs/malformed-op errors/quota-expectation/
working-source budget failures retained. Handoffs: commands/commit scope/hashes/
omitted gates, not integration/native/auth/privacy/OS durability.
