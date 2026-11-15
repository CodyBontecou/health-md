"""AS07 bounded SOURCE reference: portable review/outbox only, not native sync.

No auth, network, time, randomness, health, binding, activation or durable IO.
Only synthetic() installs an in-memory journal and the actual frozen AS05 parser.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
import hashlib
import importlib.util
from pathlib import Path
import re
import sys
from threading import RLock

from journal import Journal, JournalError, Record

# Reversible SOURCE-ONLY budgets, not product quotas/retention promises.
MAX_PROFILES = 8                 # each of local copies, links, cloud identities
MAX_OUTBOX = 8                   # includes acknowledged/conflicted/quarantined work
MAX_HISTORY = 32                 # each of actions and immutable observed revisions
MAX_ITEM_BYTES = 32_768
MAX_STATE_BYTES = 131_072         # conservative logical bytes, not Python heap size
MAX_JOURNAL_BYTES = 3 * MAX_STATE_BYTES + 4_096
SAFE_MAX = 9_007_199_254_740_991


@dataclass(frozen=True, repr=False)
class Context:
    """Fixed test sentinels + local cancellation generation, NEVER a principal."""
    issuer: str
    environment: str
    account: str
    generation: int

    def __post_init__(self):
        if (self.issuer not in ("https://issuer-a.account-sync.example", "https://issuer-b.account-sync.example")
                or self.environment not in ("synthetic-a", "synthetic-b")
                or self.account not in ("sentinel-A", "sentinel-B")
                or type(self.generation) is not int or not 0 <= self.generation <= SAFE_MAX):
            raise ValueError("invalid")

    @property
    def partition(self):
        return (self.issuer, self.environment, self.account)


@dataclass(frozen=True, repr=False)
class Candidate:
    context: Context
    raw: bytes                       # exact outer record too; never reserialized
    profile_id: str
    object_revision: int
    event_sequence: int
    order_key: int | None
    content_revision: int | None
    content: object                  # actual AS05 ValidatedContent, or None
    deleted: bool


@dataclass(frozen=True, repr=False)
class LocalCopy:
    native_id: str
    content: object                  # validated local portable user copy
    accepted: object                 # pre-existing synthetic execution marker/None


@dataclass(frozen=True, repr=False)
class Link:
    context: Context
    native_id: str
    profile_id: str
    review: str                      # portable relation/intent, NOT native binding


@dataclass(frozen=True, repr=False)
class Outbox:
    context: Context
    native_id: str
    body: bytes
    mutation_id: str
    request_hash: str
    base_revision: int
    operation: str
    profile_id: str | None
    content: object
    base: Candidate | None
    choice: str
    desired_order: int | None = None  # validated reorder metadata, never content
    status: str = "pending"
    acknowledgement: Candidate | None = None


@dataclass(frozen=True, repr=False)
class State:
    context: Context
    locals: tuple[LocalCopy, ...] = ()
    links: tuple[Link, ...] = ()
    candidates: tuple[Candidate, ...] = ()
    outbox: tuple[Outbox, ...] = ()
    history: tuple[str, ...] = ()

    def head(self, profile_id, context=None):
        """Staged head for exactly one local generation; not account authority."""
        rows = [c for c in self.candidates if c.context == (context or self.context)
                and c.profile_id == profile_id]
        return max(rows, key=lambda c: c.object_revision, default=None)

    def _known_head(self, profile_id):
        """Partition knowledge only constrains input; never remap old provenance."""
        rows = [c for c in self.candidates if c.context.partition == self.context.partition
                and c.profile_id == profile_id]
        return max(rows, key=lambda c: c.object_revision, default=None)

    @property
    def ordered_heads(self):
        ids = {c.profile_id for c in self.candidates if c.context == self.context}
        rows = [self.head(i) for i in ids]
        return tuple(sorted((c for c in rows if not c.deleted),
                            key=lambda c: (c.order_key, c.profile_id)))


@dataclass(frozen=True, repr=False)
class Request:
    context: Context
    mutation_id: str
    request_hash: str
    body: bytes


@dataclass(frozen=True)
class Result:
    code: str
    request: Request | None = None


def _codec_at(path):
    local = Path(__file__).resolve().parent.parent / "validator.py"
    source = local if path is None else Path(path).resolve()
    # Explicit read-only sparse-test configuration; never a host path in source.
    # This is source identity, NOT account trust, admission or codec qualification.
    if source.read_bytes() != local.read_bytes():
        raise ValueError("requires_action")
    name = "_as07_as05_" + hashlib.sha256(str(source).encode()).hexdigest()[:16]
    if name not in sys.modules:
        spec = importlib.util.spec_from_file_location(name, source)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    return sys.modules[name]


def _native_id(value):
    return type(value) is str and re.fullmatch(r"local-[a-z0-9-]{1,32}", value) is not None


def logical_bytes(state):
    """Conservative exact payload + fixed metadata charges; duplicates charged.

    Every inline content/reference/body is charged, even when immutable objects
    share storage. Journal fault envelopes retain <=three such states.
    """
    def content_size(c):
        return 0 if c is None else len(c.raw)
    def candidate_size(c):
        return 0 if c is None else 512 + len(c.raw) + content_size(c.content)
    return (512 + sum(512 + content_size(l.content) + content_size(l.accepted) for l in state.locals)
            + 512 * len(state.links) + sum(candidate_size(c) for c in state.candidates)
            + sum(1024 + len(e.body) + content_size(e.content) + candidate_size(e.base)
                  + candidate_size(e.acknowledgement) for e in state.outbox)
            + sum(len(h.encode()) + 16 for h in state.history))


def _bounded(state):
    return (len(state.locals) <= MAX_PROFILES and len(state.links) <= MAX_PROFILES
            and len({(c.context, c.profile_id) for c in state.candidates}) <= MAX_PROFILES
            and len(state.candidates) <= MAX_HISTORY and len(state.outbox) <= MAX_OUTBOX
            and len(state.history) <= MAX_HISTORY and logical_bytes(state) <= MAX_STATE_BYTES)


class Kernel:
    """Small portable-only interface. Default construction has zero ports/calls.

    Mutations: local(), observe(), select(), acknowledge(), switch(). Inspection:
    view(), next_request(), verify(). There is intentionally no accept/apply-native,
    page/cursor, request construction/rebase, durable restore or auth method.
    """
    def __init__(self):
        self._lock = RLock()
        self._journal = self._codec = self._current = self._record = self._state = None
        self._uncertain = None
        self._blocked_code = None

    @classmethod
    def synthetic(cls, context: Context, journal: Journal, *, codec_path=None):
        if type(context) is not Context:
            raise ValueError("invalid")
        result = cls()
        result._codec = _codec_at(codec_path)
        result._journal, result._current = journal, context
        try:
            record = journal.read()
        except JournalError:
            result._state = State(context)
            result._uncertain = (None, None, "verification_pending")
            return result
        result._record = record
        # A partial journal state is NEVER a verified visible view. Preserve the
        # actual partial state + desired intent inside the immutable journal.
        before = record.state if record.pending is None else record.pending.before
        result._state = State(context) if before is None else before
        if record.pending is not None:
            result._uncertain = (None, None, "verification_pending")
        return result

    def view(self):
        with self._lock:
            return self._state

    def _ready(self, context):
        if self._journal is None:
            return "unavailable"
        if context != self._current:
            return "quarantined"
        if self._record is None:
            return "verification_pending"
        if self._record.fence != self._current or self._state.context != self._current:
            return "fenced"
        if self._uncertain is not None:
            return self._blocked_code or "verification_pending"
        return None

    def _read_candidate(self, context, raw):
        if type(raw) is not bytes or len(raw) > MAX_ITEM_BYTES:
            raise ValueError("invalid")
        r, content = self._codec.parse_record(raw)
        return Candidate(context, raw, r["profile_id"], r["object_revision"], r["event_sequence"],
                         r["order_key"], r["content_revision"], content, r["deleted"])

    def _consistent(self, c):
        for old in self._state.candidates:
            if old.context.partition != c.context.partition:
                continue
            # The local generation is provenance/fencing, not cloud identity.
            # Exact record bytes compare immutable metadata without relabelling
            # either retained candidate's original Context.
            if old.event_sequence == c.event_sequence and old.raw != c.raw:
                return False
            if old.profile_id != c.profile_id:
                continue
            if old.deleted and not c.deleted:
                return False
            if old.object_revision == c.object_revision and old.raw != c.raw:
                return False
            if (old.content is not None and c.content is not None
                    and old.content_revision == c.content_revision and old.content.raw != c.content.raw):
                return False
        return True

    def _commit(self, state, code, *, owner=None):
        state = replace(state, history=state.history + (code,))
        if not _bounded(state) or self._record.serial >= MAX_HISTORY:
            return Result("quota_exceeded")
        expected = self._record
        desired = Record(expected.serial + 1, state.context, state)
        self._uncertain = (expected, desired, code)
        try:
            self._journal.apply(expected, expected.fence if owner is None else owner, state)
        except JournalError:
            pass
        return self.verify()

    def verify(self):
        with self._lock:
            if self._journal is None:
                return Result("unavailable")
            try:
                observed = self._journal.read()
            except JournalError:
                return Result("verification_pending")
            if observed.fence != self._current:
                self._blocked_code = "fenced"
                return Result("fenced")
            if self._uncertain is not None:
                _, desired, code = self._uncertain
                if desired is None or observed != desired or observed.pending is not None:
                    return Result("verification_pending")
                self._record, self._state, self._uncertain = observed, observed.state, None
                self._blocked_code = None
                return Result(code)
            if observed != self._record or self._state.context != self._current:
                self._uncertain = (self._record, None, "verification_pending")
                return Result("verification_pending")
            return Result("unchanged")

    def local(self, context, native_id, raw):
        """Seed a pre-existing synthetic user/accepted copy; never materialize OS state."""
        with self._lock:
            if error := self._ready(context):
                return Result(error)
            if not _native_id(native_id) or any(l.native_id == native_id for l in self._state.locals + self._state.links):
                return Result("requires_action")
            if type(raw) is not bytes or len(raw) > MAX_ITEM_BYTES:
                return Result("quota_exceeded" if type(raw) is bytes else "invalid")
            try:
                content = self._codec.ValidatedContent.parse(raw)
            except (self._codec.Invalid, ValueError):
                return Result("invalid")
            local = LocalCopy(native_id, content, content)
            return self._commit(replace(self._state, locals=self._state.locals + (local,)), "local_preserved")

    def observe(self, context, raw):
        """One explicit synthetic head event; NOT a page/revision-read authority."""
        with self._lock:
            if error := self._ready(context):
                return Result(error)
            if type(raw) is bytes and len(raw) > MAX_ITEM_BYTES:
                return Result("quota_exceeded")
            try:
                c = self._read_candidate(context, raw)
            except (self._codec.Invalid, ValueError):
                return Result("invalid")
            if not self._consistent(c):
                return Result("requires_action")
            head = self._state._known_head(c.profile_id)
            if head is not None:
                if c.object_revision < head.object_revision:
                    return Result("unchanged")
                if c.raw == head.raw:
                    return Result("unchanged")
                if (head.deleted and not c.deleted or c.object_revision <= head.object_revision
                        or c.event_sequence <= head.event_sequence):
                    return Result("requires_action")
                if not c.deleted and not head.deleted:
                    same = c.content.raw == head.content.raw
                    if ((same and c.content_revision != head.content_revision)
                            or (not same and c.content_revision <= head.content_revision)):
                        return Result("requires_action")
            dirty = any(e.context == context and e.profile_id == c.profile_id and e.status in ("pending", "conflict")
                        for e in self._state.outbox)
            code = ("edit_delete_conflict" if c.deleted else "edit_edit_conflict") if dirty else (
                "keep_local_unlink_review" if c.deleted else "pending_review")
            entries = tuple(replace(e, status="conflict") if e.context == context
                            and e.profile_id == c.profile_id and e.status == "pending" else e
                            for e in self._state.outbox)
            links = tuple(replace(l, review=code) if l.context == context and l.profile_id == c.profile_id else l
                          for l in self._state.links)
            return self._commit(replace(self._state, candidates=self._state.candidates + (c,),
                                        outbox=entries, links=links), code)

    def select(self, context, choice, native_id, payload, *, conflict_id=None):
        """Explicit synthetic publish/edit/delete/reorder/adopt/keep_both selection.

        adopt payload is an already observed cloud ID; all others are EXACT AS05
        mutation bytes. No request builder, bundle import, automatic rebase or ID
        generator. Actual protection/consent/preservation IO remain unavailable.
        """
        with self._lock:
            if error := self._ready(context):
                return Result(error)
            if choice not in ("publish", "edit", "delete", "reorder", "adopt", "keep_both") or not _native_id(native_id):
                return Result("requires_action")
            s = self._state
            if choice == "adopt":
                head = s.head(payload) if type(payload) is str else None
                if head is None:
                    return Result("not_found")
                if head.deleted:
                    return Result("gone")
                existing = next((l for l in s.links if l.context == context and l.profile_id == payload), None)
                if existing is not None:
                    return Result("pending_review" if existing.native_id == native_id else "requires_action")
                if any(l.native_id == native_id for l in s.locals + s.links):
                    return Result("requires_action")
                link = Link(context, native_id, head.profile_id, "pending_review")
                return self._commit(replace(s, links=s.links + (link,)), "pending_review")
            if type(payload) is not bytes or len(payload) > MAX_ITEM_BYTES:
                return Result("quota_exceeded" if type(payload) is bytes else "invalid")
            try:
                m, content = self._codec.parse_mutation(payload)
            except (self._codec.Invalid, ValueError, TypeError):
                # Frozen AS05 rejects unhashable mistyped operation values by
                # TypeError; the caller still returns a fixed invalid refusal.
                return Result("invalid")
            # Idempotency belongs to the owner partition, NOT local generation.
            prior = next((e for e in s.outbox if e.context.partition == context.partition
                          and e.mutation_id == m["mutation_id"]), None)
            if prior is not None:
                if prior.body != payload:
                    return Result("idempotency_mismatch")
                if prior.context != context:
                    return Result("quarantined")
                return Result("unchanged" if prior.native_id == native_id and prior.choice == choice else "requires_action")
            op = m["operation"]
            required_op = {"publish": "create", "keep_both": "create", "edit": "update",
                           "delete": "delete", "reorder": "reorder"}[choice]
            if op != required_op:
                return Result("requires_action")
            local = next((l for l in s.locals if l.native_id == native_id), None)
            base = None
            if choice == "publish":
                if local is None or local.content.raw != content.raw or any(l.native_id == native_id for l in s.links):
                    return Result("requires_action")
                if any(e.native_id == native_id and e.status in ("pending", "conflict") for e in s.outbox):
                    return Result("requires_action")
            elif choice == "keep_both":
                source = next((e for e in s.outbox if e.context == context and e.mutation_id == conflict_id
                               and e.status == "conflict"), None)
                if (source is None or source.content is None or source.content.raw != content.raw
                        or local is not None or any(l.native_id == native_id for l in s.links)):
                    return Result("requires_action")
                s = replace(s, locals=s.locals + (LocalCopy(native_id, content, None),))
            else:
                link = next((l for l in s.links if l.context == context and l.native_id == native_id), None)
                if link is None or link.profile_id != m["profile_id"]:
                    return Result("not_found")
                base = s.head(link.profile_id)
                if base is None:
                    return Result("not_found")
                if base.deleted:
                    return Result("gone")
                if (choice != "reorder" and local is None) or base.object_revision != m["base_revision"]:
                    return Result("requires_action")
                if any(e.context == context and e.profile_id == base.profile_id and e.status in ("pending", "conflict")
                       for e in s.outbox):
                    return Result("requires_action")
            if op == "reorder":
                content = base.content  # exact immutable captured reference, not an overlay
            entry = Outbox(context, native_id, payload, m["mutation_id"], self._codec.mutation_digest(payload),
                           m["base_revision"], op, m.get("profile_id"), content, base, choice, m.get("order_key"))
            return self._commit(replace(s, outbox=s.outbox + (entry,)), "queued")

    def next_request(self):
        """Inspect oldest eligible EXACT captured body; never dispatch any port."""
        with self._lock:
            if error := self._ready(self._current):
                return Result(error)
            verified = self.verify()
            if verified.code != "unchanged":
                return verified
            entry = next((e for e in self._state.outbox if e.context == self._current and e.status == "pending"), None)
            if entry is None:
                return Result("requires_action")
            if (self._record.serial >= MAX_HISTORY
                    or not _bounded(replace(self._state, history=self._state.history + ("quarantined",)))):
                return Result("quota_exceeded")
            return Result("pending", Request(entry.context, entry.mutation_id, entry.request_hash, entry.body))

    def _quarantine(self, entry):
        entries = tuple(replace(e, status="quarantined") if e == entry else e for e in self._state.outbox)
        return self._commit(replace(self._state, outbox=entries), "quarantined")

    def _ack_matches(self, entry, c):
        if entry.operation == "create":
            return (not c.deleted and c.object_revision == c.content_revision == 1
                    and c.content.raw == entry.content.raw
                    and not any(old.context.partition == c.context.partition and old.profile_id == c.profile_id
                                for old in self._state.candidates))
        base = entry.base
        if c.profile_id != entry.profile_id:
            return False
        if entry.operation == "delete":
            return (c.deleted and c.object_revision == base.object_revision + 1
                    and c.event_sequence > base.event_sequence)
        if entry.operation == "reorder":
            if (c.deleted or c.content.raw != base.content.raw or c.content.sha256 != base.content.sha256
                    or c.content_revision != base.content_revision or c.order_key != entry.desired_order):
                return False
            if entry.desired_order == base.order_key:
                return (c.object_revision == base.object_revision and c.event_sequence == base.event_sequence)
            # Actual AS05 parsing bounds every counter first; overflow can never
            # wrap into a valid success. Receipt is not a latest-head proof.
            return c.object_revision == base.object_revision + 1 and c.event_sequence > base.event_sequence
        if c.deleted or c.content.raw != entry.content.raw or c.order_key != base.order_key:
            return False
        if base.content.raw == entry.content.raw:  # exact server no-op receipt
            return (c.object_revision == base.object_revision and c.content_revision == base.content_revision
                    and c.event_sequence == base.event_sequence)
        return (c.object_revision == base.object_revision + 1 and c.content_revision == base.content_revision + 1
                and c.event_sequence > base.event_sequence)

    def acknowledge(self, context, mutation_id, request_hash, raw):
        """Synthetic correlated receipt, NOT authentication/latest-head proof."""
        with self._lock:
            if self._journal is None:
                return Result("unavailable")
            if error := self._ready(self._current):
                return Result(error)
            entry = next((e for e in self._state.outbox if e.context.partition == self._current.partition
                          and e.mutation_id == mutation_id), None)
            if entry is None:
                return Result("quarantined" if context != self._current else "not_found")
            if entry.status == "quarantined" or entry.context != self._current:
                return Result("quarantined")
            if context != entry.context or request_hash != entry.request_hash:
                return self._quarantine(entry)
            if type(raw) is bytes and len(raw) > MAX_ITEM_BYTES:
                return Result("quota_exceeded")
            try:
                c = self._read_candidate(context, raw)
            except (self._codec.Invalid, ValueError):
                return self._quarantine(entry)
            if entry.status == "acknowledged":
                return Result("unchanged") if c == entry.acknowledgement else self._quarantine(entry)
            first = next((e for e in self._state.outbox if e.context == context and e.status == "pending"), None)
            if entry.status != "pending" or entry != first:
                return Result("requires_action")
            if not self._ack_matches(entry, c) or not self._consistent(c):
                return self._quarantine(entry)
            entries = tuple(replace(e, status="acknowledged", acknowledgement=c) if e == entry else e
                            for e in self._state.outbox)
            links = self._state.links
            code = "keep_local_unlink_review" if c.deleted else "pending_review"
            if entry.operation == "create":
                links += (Link(context, entry.native_id, c.profile_id, code),)
            else:
                links = tuple(replace(l, review=code) if l.context == context and l.profile_id == c.profile_id else l
                              for l in links)
            candidates = self._state.candidates
            if c not in candidates:
                candidates += (c,)
            return self._commit(replace(self._state, outbox=entries, links=links, candidates=candidates), code)

    def switch(self, context):
        """Immediate local fence even if journal quota/fault prevents recording it.

        Local copies/accepted markers survive. All old mappings/candidates retain
        their original owner. No old work becomes eligible in a new generation.
        """
        with self._lock:
            if self._journal is None:
                return Result("unavailable")
            if type(context) is not Context or context.generation <= self._current.generation:
                return Result("requires_action")
            old = self._current
            error = self._ready(old)
            self._current = context
            if error:
                return Result("fenced")
            s = replace(self._state, context=context,
                        outbox=tuple(replace(e, status="quarantined") for e in self._state.outbox),
                        links=tuple(replace(l, review="quarantined") for l in self._state.links))
            return self._commit(s, "quarantined", owner=old)
