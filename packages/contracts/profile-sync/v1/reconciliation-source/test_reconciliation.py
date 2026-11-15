"""Finite SOURCE tests. All filesystem IO reads frozen sources/fixtures only.

Inputs/expected trace outputs are independently specified in source-vectors.json;
this file does not import AS05 scenario predicates or generate output goldens.
"""
import argparse
import ast
from dataclasses import FrozenInstanceError, replace
import hashlib
import io
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

import model
from model import Context, Kernel, Result
from journal import FaultJournal, MemoryJournal, JournalError

HERE = Path(__file__).resolve().parent
AS05 = HERE.parent
CODEC_PATH = os.environ.get("AS07_CODEC_PATH")
VECTORS_SHA256 = "049da30dd6ae1e5e9f3ff3f472936db98721bd6d2a85190c777e4c4212a34555"


def encode(value):
    # Input encoding convention ONLY, not a canonicalizer in the kernel.
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def request_hash(raw):
    return hashlib.sha256(b"healthmd.profile_sync.mutate/v1\x00" + raw).hexdigest()


class SourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw_vectors = (HERE / "fixtures/source-vectors.json").read_bytes()
        cls.vectors = json.loads(cls.raw_vectors)
        cls.contexts = {k: Context(*v) for k, v in cls.vectors["contexts"].items()}
        cls.content = {k: (AS05 / "fixtures" / v["file"]).read_bytes()
                       for k, v in cls.vectors["content"].items()}
        cls.profiles = cls.vectors["profiles"]
        cls.bodies, cls.records = cls.inputs()

    @classmethod
    def inputs(cls):
        bodies, records = {}, {}
        for key, v in cls.vectors["mutations"].items():
            body = {"schema": "healthmd.profile_sync", "schema_version": 1,
                    "operation": v["operation"], "mutation_id": v["key"], "base_revision": v["base"]}
            if "profile" in v:
                body["profile_id"] = cls.profiles[v["profile"]]
            if "content" in v:
                body["content_json"] = cls.content[v["content"]].decode()
                body["content_hash"] = cls.vectors["content"][v["content"]]["hash"]
            bodies[key] = encode(body)
        for key, v in cls.vectors["records"].items():
            deleted = v.get("deleted", False)
            row = {"schema": "healthmd.profile_sync", "schema_version": 1,
                   "profile_id": cls.profiles[v["profile"]], "object_revision": v["object"],
                   "event_sequence": v["event"], "deleted": deleted,
                   "order_key": None if deleted else v["order"],
                   "content_revision": None if deleted else v["revision"],
                   "content_json": None if deleted else cls.content[v["content"]].decode(),
                   "content_hash": None if deleted else cls.vectors["content"][v["content"]]["hash"]}
            records[key] = encode(row)
        return bodies, records

    def make(self, *, context=None, journal=None):
        ctx = context or self.contexts["a"]
        j = journal or MemoryJournal(ctx)
        return Kernel.synthetic(ctx, j, codec_path=CODEC_PATH), j

    def code(self, result, expected):
        self.assertEqual(result.code, expected)
        self.assertIsNone(result.request)

    def seeded(self, *, journal=None):
        k, j = self.make(journal=journal)
        self.code(k.local(self.contexts["a"], "local-one", self.content["base"]), "local_preserved")
        return k, j

    def published(self, *, journal=None):
        k, j = self.seeded(journal=journal)
        self.code(k.select(self.contexts["a"], "publish", "local-one", self.bodies["create"]), "queued")
        self.code(k.acknowledge(self.contexts["a"], self.vectors["mutations"]["create"]["key"],
                               request_hash(self.bodies["create"]), self.records["first"]), "pending_review")
        return k, j

    def test_authored_fixture_integrity_reproducibility_and_actual_parsers(self):
        self.assertEqual(hashlib.sha256(self.raw_vectors).hexdigest(), VECTORS_SHA256)
        self.assertEqual(self.inputs(), (self.bodies, self.records))
        self.assertEqual(len(self.vectors["traces"]), 15)
        k, j = self.make()
        self.assertEqual(j.calls, (1, 0))  # zero selected/transferred profiles
        self.assertEqual(k.view().locals + k.view().outbox + k.view().candidates, ())
        codec = k._codec
        self.assertEqual(Path(codec.__file__).read_bytes(), (AS05 / "validator.py").read_bytes())
        self.assertEqual(hashlib.sha256(Path(codec.__file__).read_bytes()).hexdigest(),
                         "fa01a80741f793bd7265a38d3af95bb3cbc56c25f97ae509937383d0f3f31e52")
        for key, raw in self.content.items():
            c = codec.ValidatedContent.parse(raw, self.vectors["content"][key]["hash"])
            self.assertEqual(c.raw, raw)
            self.assertEqual(c.sha256, hashlib.sha256(b"healthmd.profile_sync.portable/v1\0" + raw).hexdigest())
        for raw in self.bodies.values():
            parsed, content = codec.parse_mutation(raw)
            self.assertEqual(parsed["base_revision"], json.loads(raw)["base_revision"])
            self.assertEqual(codec.mutation_digest(raw), request_hash(raw))
            if content is not None:
                self.assertEqual(content.raw, parsed["content_json"].encode())
        for raw in self.records.values():
            parsed, content = codec.parse_record(raw)
            self.assertEqual(content is None, parsed["deleted"])

    def run_trace(self, trace):
        a, ctx = self.contexts["a"], self.contexts["a"]
        j = FaultJournal(ctx)
        k, _ = self.make(journal=j)
        journal_totals = [0, 0]
        observed = []
        for step in trace["steps"]:
            op = step[0]
            with self.subTest(trace=trace["id"], step=op):
                if op == "arm":
                    j.arm(step[1], replacement=self.contexts[step[2]] if len(step) == 3 else None)
                    continue
                if op == "readable":
                    j.make_readable()
                    continue
                if op == "local":
                    result = k.local(ctx, step[2], self.content[step[1]])
                elif op == "select":
                    result = k.select(ctx, step[1], step[3], self.bodies[step[2]])
                elif op == "keep":
                    result = k.select(ctx, "keep_both", step[3], self.bodies[step[1]],
                                      conflict_id=self.vectors["mutations"][step[2]]["key"])
                elif op == "adopt":
                    result = k.select(ctx, "adopt", step[2], self.profiles[step[1]])
                elif op == "changed_bytes":
                    result = k.select(ctx, "publish", "local-one", self.bodies[step[1]] + b" ")
                elif op == "observe":
                    result = k.observe(ctx, self.records[step[1]])
                elif op == "ack":
                    result = k.acknowledge(a, self.vectors["mutations"][step[1]]["key"],
                                           request_hash(self.bodies[step[1]]), self.records[step[2]])
                elif op == "switch":
                    ctx = self.contexts[step[1]]
                    result = k.switch(ctx)
                elif op == "next":
                    result = k.next_request()
                    if step[1] is not None:
                        self.assertEqual(result.request.body, self.bodies[step[1]])
                        self.assertEqual(result.request.mutation_id, self.vectors["mutations"][step[1]]["key"])
                        self.assertEqual(result.request.request_hash, request_hash(self.bodies[step[1]]))
                        self.assertEqual(result.request.context, ctx)
                    else:
                        self.assertIsNone(result.request)
                elif op == "verify":
                    result = k.verify()
                elif op == "restart":
                    # Exact same-interface read snapshot, no serialization/file/OS restart.
                    saved = j.read()
                    journal_totals = [n + v for n, v in zip(journal_totals, j.calls)]
                    j = FaultJournal(ctx, record=saved)
                    k, _ = self.make(context=ctx, journal=j)
                    self.assertEqual(j.read(), saved)
                    # Account for this extra actual integrity read in the fixture runner.
                    result = k.verify()
                else:
                    self.fail("unknown independently specified step")
                self.assertEqual(result.code, step[-1])
                observed.append(result.code)
        s = k.view()
        actual = {"locals": len(s.locals), "links": len(s.links), "candidates": len(s.candidates),
                  "statuses": [e.status for e in s.outbox], "history": list(s.history)}
        self.assertEqual(actual, trace["final"])
        if trace["id"] == "identical-names-two-identities-total-order":
            heads = s.ordered_heads
            self.assertEqual([c.profile_id for c in heads], [self.profiles["p1"], self.profiles["p2"]])
            self.assertEqual([c.order_key for c in heads], [2, 2])
            self.assertEqual([c.content_revision for c in heads], [1, 1])
            self.assertEqual([c.content.sha256 for c in heads], [self.vectors["content"]["base"]["hash"]] * 2)
            self.assertEqual([c.content.raw for c in heads], [self.content["base"]] * 2)
            self.assertEqual([c.context for c in heads], [a, a])
        for l in s.locals:
            if l.native_id in ("local-one", "local-two") and l.accepted is not None:
                self.assertEqual(l.content.raw, self.content["base"])
                self.assertEqual(l.accepted.raw, self.content["base"])
        for entry in s.outbox:
            key = next(key for key, row in self.vectors["mutations"].items() if row["key"] == entry.mutation_id)
            self.assertEqual(entry.body, self.bodies[key])
            self.assertEqual(entry.request_hash, request_hash(entry.body))
            self.assertEqual(entry.context, a)
        for c in s.candidates:
            self.assertIn(c.raw, self.records.values())
            if c.content is not None:
                self.assertIn(c.content.raw, self.content.values())
        record = j.read()
        if "pending" in trace:
            self.assertIsNotNone(record.pending)
            self.assertEqual(len(record.pending.desired.outbox), trace["pending"]["outbox"])
            self.assertEqual(len(record.state.outbox), trace["pending"]["actual_outbox"])
            self.assertEqual(record.pending.desired.outbox[-1].body, self.bodies["create"])
            self.assertEqual(s, record.pending.before)
        else:
            self.assertIsNone(record.pending)
            self.assertEqual(record.state, s)
        totals = tuple(n + v for n, v in zip(journal_totals, j.calls))
        self.assertEqual(totals, tuple(trace["calls"]))
        self.assertEqual(totals[1], len(trace["final"]["history"]) + int("pending" in trace))
        self.assertLessEqual(model.logical_bytes(s), model.MAX_STATE_BYTES)
        return tuple(observed), actual, totals

    def test_independent_traces_execute_real_state_transitions_twice(self):
        for trace in self.vectors["traces"]:
            with self.subTest(trace=trace["id"]):
                self.assertEqual(self.run_trace(trace), self.run_trace(trace))

    def test_default_unavailable_zero_ports_reads_or_parser_calls(self):
        with patch("model._codec_at", side_effect=AssertionError("unexpected codec call")):
            k = Kernel()
            self.assertIsNone(k.view())
            self.code(k.local(None, None, None), "unavailable")
            self.code(k.observe(None, b"private"), "unavailable")
            self.code(k.select(None, "publish", None, b"private"), "unavailable")
            self.code(k.acknowledge(None, None, None, b"private"), "unavailable")
            self.code(k.switch(None), "unavailable")
            self.code(k.next_request(), "unavailable")
            self.code(k.verify(), "unavailable")
            self.assertIsNone(k._journal)
            self.assertIsNone(k._codec)
        with self.assertRaisesRegex(ValueError, "^invalid$"):
            Context("https://real.invalid", "production", "user", 0)

    def test_actual_parser_invocations_and_fixed_nonreflecting_results(self):
        k, j = self.seeded()
        codec = k._codec
        with patch.object(codec, "parse_mutation", wraps=codec.parse_mutation) as mutation:
            self.code(k.select(self.contexts["a"], "publish", "local-one", self.bodies["create"]), "queued")
            self.assertEqual(mutation.call_args.args, (self.bodies["create"],))
        with patch.object(codec, "parse_record", wraps=codec.parse_record) as record:
            self.code(k.observe(self.contexts["a"], self.records["first"]), "pending_review")
            self.assertEqual(record.call_args.args, (self.records["first"],))
        # Conservative arrival-order omission: even a legitimate create head
        # observed before its lost acknowledgement is not trusted as a receipt.
        self.code(k.acknowledge(self.contexts["a"], self.vectors["mutations"]["create"]["key"],
                               request_hash(self.bodies["create"]), self.records["first"]), "quarantined")
        self.assertEqual(k.view().outbox[0].status, "quarantined")
        self.assertEqual(len(k.view().candidates), 1)
        self.assertEqual(k.view().links, ())
        for raw in (b'{"schema":"healthmd.profile_sync","schema_version":1,"schema_version":1}',
                    b'\xff', b'{"schema":"healthmd.profile_sync","schema_version":2}'):
            before, calls = k.view(), j.calls
            result = k.observe(self.contexts["a"], raw)
            self.code(result, "invalid")
            self.assertEqual(repr(result), "Result(code='invalid', request=None)")
            self.assertIs(k.view(), before)
            self.assertEqual(j.calls, calls)

    def test_candidate_content_mutation_and_accepted_markers_are_immutable_exact(self):
        k, _ = self.published()
        old = k.view()
        self.code(k.observe(self.contexts["a"], self.records["remote_edit"]), "pending_review")
        new = k.view()
        self.assertIs(new.locals[0], old.locals[0])
        self.assertEqual(new.locals[0].accepted.raw, self.content["base"])
        self.assertEqual(new.head(self.profiles["p1"]).content.raw, self.content["remote"])
        for obj, name, value in ((new.locals[0], "native_id", "local-other"),
                                 (new.candidates[0], "object_revision", 99),
                                 (new.outbox[0], "body", b"changed"),
                                 (new.locals[0].accepted, "raw", b"changed")):
            with self.assertRaises((FrozenInstanceError, AttributeError)):
                setattr(obj, name, value)
        # No reserializing/normalizing accepted foreign extension or Unicode bytes.
        self.assertEqual(new.candidates[0].content.raw, self.content["base"])
        self.assertIn("e\u0301".encode(), self.content["remote"])
        self.assertFalse(hasattr(k, "accept"))
        self.assertFalse(hasattr(k, "apply_native"))

    def test_wrong_issuer_environment_account_generation_ack_quarantines_work(self):
        for key in ("a1", "b1", "env1", "issuer1"):
            with self.subTest(context=key):
                k, j = self.seeded()
                self.code(k.select(self.contexts["a"], "publish", "local-one", self.bodies["create"]), "queued")
                before = k.view().locals[0]
                self.code(k.acknowledge(self.contexts[key], self.vectors["mutations"]["create"]["key"],
                                       request_hash(self.bodies["create"]), self.records["first"]), "quarantined")
                self.assertEqual(k.view().outbox[0].status, "quarantined")
                self.assertEqual(k.view().candidates, ())
                self.assertIs(k.view().locals[0], before)
                self.code(k.next_request(), "requires_action")

    def test_switch_preserves_original_partition_and_never_new_account_replay(self):
        for key in ("a1", "b1", "env1", "issuer1"):
            with self.subTest(context=key):
                k, j = self.seeded()
                a, b = self.contexts["a"], self.contexts[key]
                self.code(k.select(a, "publish", "local-one", self.bodies["create"]), "queued")
                original = k.view().outbox[0]
                self.code(k.switch(b), "quarantined")
                self.code(k.observe(a, self.records["first"]), "quarantined")
                self.code(k.select(a, "publish", "local-one", self.bodies["create"]), "quarantined")
                self.code(k.acknowledge(a, original.mutation_id, original.request_hash, self.records["first"]), "quarantined")
                self.code(k.next_request(), "requires_action")
                self.assertEqual(k.view().outbox[0].context, original.context)
                self.assertEqual(k.view().outbox[0].body, original.body)
                if b.partition == a.partition:
                    self.code(k.select(b, "publish", "local-one", self.bodies["create"]), "quarantined")

    def test_ack_checks_original_hash_operation_base_and_content_not_cached_metadata(self):
        k, _ = self.seeded()
        self.code(k.select(self.contexts["a"], "publish", "local-one", self.bodies["create"]), "queued")
        key = self.vectors["mutations"]["create"]["key"]
        for field, value in (("object_revision", 2), ("content_revision", 2), ("deleted", True),
                             ("content_json", self.content["edit"].decode())):
            with self.subTest(field=field):
                fresh, _ = self.seeded()
                self.code(fresh.select(self.contexts["a"], "publish", "local-one", self.bodies["create"]), "queued")
                changed = dict(json.loads(self.records["first"]), **{field: value})
                self.code(fresh.acknowledge(self.contexts["a"], key, request_hash(self.bodies["create"]), encode(changed)), "quarantined")
                self.assertEqual(fresh.view().links, ())
        self.code(k.acknowledge(self.contexts["a"], key, "0" * 64, self.records["first"]), "quarantined")
        for field, value in (("object_revision", 1), ("content_revision", 1), ("order_key", 3), ("profile_id", self.profiles["p2"])):
            with self.subTest(update_field=field):
                edit, _ = self.published()
                self.code(edit.select(self.contexts["a"], "edit", "local-one", self.bodies["edit"]), "queued")
                changed = dict(json.loads(self.records["remote_edit"]), content_json=self.content["edit"].decode(),
                               content_hash=self.vectors["content"]["edit"]["hash"])
                changed[field] = value
                self.code(edit.acknowledge(self.contexts["a"], self.vectors["mutations"]["edit"]["key"],
                                          request_hash(self.bodies["edit"]), encode(changed)), "quarantined")
                self.assertEqual(edit.view().locals[0].accepted.raw, self.content["base"])

    def test_edit_and_delete_receipts_and_delete_edit_conflict(self):
        k, _ = self.published()
        self.code(k.select(self.contexts["a"], "edit", "local-one", self.bodies["edit"]), "queued")
        row = dict(json.loads(self.records["remote_edit"]), content_json=self.content["edit"].decode(),
                   content_hash=self.vectors["content"]["edit"]["hash"])
        self.code(k.acknowledge(self.contexts["a"], self.vectors["mutations"]["edit"]["key"],
                               request_hash(self.bodies["edit"]), encode(row)), "pending_review")
        self.assertEqual(k.view().head(self.profiles["p1"]).content.raw, self.content["edit"])
        deleted, _ = self.published()
        self.code(deleted.select(self.contexts["a"], "delete", "local-one", self.bodies["delete"]), "queued")
        self.code(deleted.acknowledge(self.contexts["a"], self.vectors["mutations"]["delete"]["key"],
                                     request_hash(self.bodies["delete"]), self.records["deleted"]), "keep_local_unlink_review")
        self.assertEqual(deleted.view().locals[0].content.raw, self.content["base"])
        conflict, _ = self.published()
        self.code(conflict.select(self.contexts["a"], "delete", "local-one", self.bodies["delete"]), "queued")
        self.code(conflict.observe(self.contexts["a"], self.records["remote_edit"]), "edit_edit_conflict")
        self.assertEqual(conflict.view().outbox[-1].operation, "delete")
        self.assertEqual(conflict.view().outbox[-1].base.raw, self.records["first"])
        self.assertEqual(conflict.view().outbox[-1].body, self.bodies["delete"])
        self.assertEqual(conflict.view().outbox[-1].status, "conflict")

    def test_old_repeated_inconsistent_events_no_resurrection_or_reference_rewrite(self):
        k, j = self.published()
        self.code(k.observe(self.contexts["a"], self.records["remote_edit"]), "pending_review")
        before, calls = k.view(), j.calls
        self.code(k.observe(self.contexts["a"], self.records["first"]), "unchanged")
        self.code(k.observe(self.contexts["a"], self.records["remote_edit"]), "unchanged")
        inconsistent = dict(json.loads(self.records["remote_edit"]), content_revision=1)
        self.code(k.observe(self.contexts["a"], encode(inconsistent)), "requires_action")
        self.assertIs(k.view(), before)
        self.assertEqual(j.calls, calls)
        self.code(k.observe(self.contexts["a"], encode(dict(json.loads(self.records["deleted"]), object_revision=3, event_sequence=3))), "keep_local_unlink_review")
        resurrection = dict(json.loads(self.records["remote_edit"]), object_revision=4, event_sequence=4, content_revision=3)
        self.code(k.observe(self.contexts["a"], encode(resurrection)), "requires_action")

    def test_ordering_does_not_change_content_or_accepted_snapshot(self):
        k, _ = self.published()
        row = dict(json.loads(self.records["first"]), object_revision=2, event_sequence=2, order_key=0)
        self.code(k.observe(self.contexts["a"], encode(row)), "pending_review")
        self.assertEqual(k.view().head(self.profiles["p1"]).content_revision, 1)
        self.assertEqual(k.view().head(self.profiles["p1"]).content.raw, self.content["base"])
        self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])
        heads = k.view().ordered_heads
        self.assertEqual([c.profile_id for c in heads], [self.profiles["p1"]])
        self.assertEqual([c.order_key for c in heads], [0])
        self.assertEqual([c.content_revision for c in heads], [1])
        self.assertEqual([c.content.sha256 for c in heads], [self.vectors["content"]["base"]["hash"]])
        self.assertEqual([c.content.raw for c in heads], [self.content["base"]])
        self.assertEqual([c.context for c in heads], [self.contexts["a"]])
        # Explicit outbound reorder is metadata only; pages/resets remain absent.
        reorder = {"schema": "healthmd.profile_sync", "schema_version": 1, "operation": "reorder",
                   "mutation_id": "psm_" + "7" * 32, "profile_id": self.profiles["p1"], "base_revision": 2, "order_key": 1}
        self.code(k.select(self.contexts["a"], "reorder", "local-one", encode(reorder)), "queued")
        entry = k.view().outbox[-1]
        self.assertEqual((entry.operation, entry.desired_order, entry.base_revision), ("reorder", 1, 2))
        self.assertEqual(entry.base.raw, encode(row))
        self.assertEqual(entry.content.raw, self.content["base"])
        self.assertEqual(k.next_request().request.body, encode(reorder))
        receipt = encode(dict(row, object_revision=3, event_sequence=3, order_key=1))
        self.code(k.acknowledge(self.contexts["a"], "psm_77777777777777777777777777777777",
                               request_hash(encode(reorder)), receipt), "pending_review")
        head = k.view().head(self.profiles["p1"])
        self.assertEqual((head.object_revision, head.event_sequence, head.order_key, head.content_revision), (3, 3, 1, 1))
        self.assertEqual(head.content.raw, self.content["base"])
        self.assertEqual(head.content.sha256, "315912058e734b1613fb4b4775dbf8bd78944641151e8bd559eaa47e21e38750")
        self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])
        self.assertEqual(k.view().ordered_heads, (head,))
        page = {"schema": "healthmd.profile_sync", "schema_version": 1, "mode": "snapshot", "snapshot_id": "pss_" + "1" * 32,
                "high_watermark": 2, "items": [], "next_cursor": None, "complete": True}
        self.code(k.observe(self.contexts["a"], encode(page)), "invalid")

    def test_exclusive_expected_state_real_competing_kernels_and_readback(self):
        k, j = self.seeded()
        peer, _ = self.make(journal=j)
        before = j.read()
        self.code(k.select(self.contexts["a"], "publish", "local-one", self.bodies["create"]), "queued")
        self.code(peer.select(self.contexts["a"], "publish", "local-one", self.bodies["second"]), "verification_pending")
        actual = j.read()
        self.assertEqual(actual.serial, before.serial + 1)
        self.assertEqual(len(actual.state.outbox), 1)
        self.assertEqual(actual.state.outbox[0].body, self.bodies["create"])
        self.assertEqual(peer._uncertain[1].state.outbox[0].body, self.bodies["second"])
        self.assertIsNone(actual.pending)
        self.code(peer.next_request(), "verification_pending")
        self.assertEqual(j.calls[1], 3)  # seed, one winner, one genuine CAS loser

    def test_commit_unreadable_never_guesses_success_or_rolls_back(self):
        a = self.contexts["a"]
        j = FaultJournal(a)
        k, _ = self.seeded(journal=j)
        before = k.view()
        j.arm("unreadable")
        self.code(k.select(a, "publish", "local-one", self.bodies["create"]), "verification_pending")
        self.assertIs(k.view(), before)
        self.assertEqual(k._uncertain[1].state.outbox[0].body, self.bodies["create"])
        self.code(k.next_request(), "verification_pending")
        self.code(k.select(a, "publish", "local-one", self.bodies["second"]), "verification_pending")
        with self.assertRaisesRegex(JournalError, "^verification_pending$"):
            j.read()
        j.make_readable()
        actual = j.read()
        self.assertEqual(actual.state.outbox[0].body, self.bodies["create"])
        self.code(k.verify(), "queued")
        self.assertEqual(j.read(), actual)
        self.assertEqual(j.calls[1], 2)  # no compensating write/rollback

    def test_journal_fault_at_receipt_keeps_accepted_copy_and_exact_pending_body(self):
        for fault in ("no_op", "partial", "unreadable", "stale_owner"):
            with self.subTest(fault=fault):
                a = self.contexts["a"]
                j = FaultJournal(a)
                k, _ = self.seeded(journal=j)
                self.code(k.select(a, "publish", "local-one", self.bodies["create"]), "queued")
                before = k.view()
                j.arm(fault, replacement=self.contexts["a1"])
                self.code(k.acknowledge(a, self.vectors["mutations"]["create"]["key"],
                                       request_hash(self.bodies["create"]), self.records["first"]),
                          "fenced" if fault == "stale_owner" else "verification_pending")
                self.assertIs(k.view(), before)
                self.assertEqual(k.view().outbox[0].body, self.bodies["create"])
                self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])
                if fault == "unreadable":
                    j.make_readable()
                actual = j.read()
                if fault == "no_op":
                    self.assertEqual(actual.state, before)
                    self.assertEqual(actual.pending.desired.outbox[0].status, "acknowledged")
                elif fault == "partial":
                    self.assertEqual(actual.state.outbox[0].status, "pending")
                    self.assertEqual(actual.state.candidates[0].raw, self.records["first"])
                    self.assertEqual(actual.state.links[0].profile_id, self.profiles["p1"])
                    self.assertEqual(actual.pending.desired.outbox[0].status, "acknowledged")
                elif fault == "unreadable":
                    self.assertEqual(actual.state.outbox[0].status, "acknowledged")
                    self.code(k.verify(), "pending_review")
                else:
                    self.assertEqual(actual.fence, self.contexts["a1"])
                    self.assertEqual(actual.state, before)
                    self.assertEqual(actual.pending.desired.outbox[0].status, "acknowledged")

    def test_bounds_preserve_every_old_work_item_and_immediate_local_fence(self):
        a = self.contexts["a"]
        k, j = self.make()
        for i in range(model.MAX_PROFILES):
            self.code(k.local(a, f"local-{i}", self.content["current"]), "local_preserved")
        before, calls = j.read(), j.calls
        self.code(k.local(a, "local-extra", self.content["current"]), "quota_exceeded")
        self.assertEqual(j.read(), before)
        self.assertEqual(j.calls[1], calls[1])
        # Eight retained pending bodies fit; a ninth is refused without eviction.
        for i in range(model.MAX_OUTBOX):
            raw = dict(json.loads(self.bodies["create"]), mutation_id="psm_" + f"{i:032x}",
                       content_json=self.content["current"].decode(), content_hash=self.vectors["content"]["current"]["hash"])
            self.code(k.select(a, "publish", f"local-{i}", encode(raw)), "queued")
        before = j.read()
        new = dict(json.loads(self.bodies["create"]), mutation_id="psm_" + "8" * 32)
        # Can't select a duplicate local pending publication even before quota.
        self.code(k.select(a, "publish", "local-0", encode(new)), "requires_action")
        self.assertEqual(j.read(), before)
        current_row = dict(json.loads(self.records["first"]), content_json=self.content["current"].decode(),
                           content_hash=self.vectors["content"]["current"]["hash"])
        first_key = "psm_" + "0" * 32
        first_body = k.view().outbox[0].body
        self.code(k.acknowledge(a, first_key, request_hash(first_body), encode(current_row)), "pending_review")
        ninth = dict(json.loads(k.view().outbox[0].body), operation="update", base_revision=1,
                     profile_id=self.profiles["p1"], mutation_id="psm_" + "8" * 32)
        before = j.read()
        self.code(k.select(a, "edit", "local-0", encode(ninth)), "quota_exceeded")
        self.assertEqual(j.read(), before)
        self.assertEqual(len(k.view().outbox), model.MAX_OUTBOX)
        # No patched budgets: exhaust actual action history with generation-only
        # source fences, then fence locally even though the journal is full.
        history, hj = self.make()
        for i in range(1, model.MAX_HISTORY + 1):
            next_context = replace(a, generation=i)
            self.code(history.switch(next_context), "quarantined")
        hbefore = hj.read()
        self.code(history.switch(replace(a, generation=model.MAX_HISTORY + 1)), "quota_exceeded")
        self.code(history.next_request(), "fenced")
        self.assertEqual(hj.read(), hbefore)

    def test_byte_budget_exhaustion_preserves_original_large_valid_content(self):
        a = self.contexts["a"]
        source = json.loads(self.content["current"])
        source["profile"]["presentation"]["markdown"]["custom_text"] = "Synthetic " + "x" * 26_000
        raw = encode(source)
        k, j = self.make()
        parsed = k._codec.ValidatedContent.parse(raw)
        self.assertLess(len(raw), model.MAX_ITEM_BYTES)
        self.code(k.local(a, "local-large", raw), "local_preserved")
        create = dict(json.loads(self.bodies["create"]), content_json=raw.decode(), content_hash=parsed.sha256)
        self.code(k.select(a, "publish", "local-large", encode(create)), "queued")
        before = j.read()
        row = dict(json.loads(self.records["first"]), content_json=raw.decode(), content_hash=parsed.sha256)
        self.code(k.acknowledge(a, create["mutation_id"], request_hash(encode(create)), encode(row)), "quota_exceeded")
        self.assertEqual(j.read(), before)
        self.assertEqual(k.view().outbox[0].body, encode(create))
        self.assertEqual(k.next_request().request.body, encode(create))
        # Per-input capacity is SOURCE quota, not permission to quarantine or
        # rewrite a valid receipt/body just to shrink it.
        oversized = encode(row) + b" " * model.MAX_ITEM_BYTES
        before = j.read()
        self.code(k.observe(a, oversized), "quota_exceeded")
        self.code(k.acknowledge(a, create["mutation_id"], request_hash(encode(create)), oversized), "quota_exceeded")
        self.assertEqual(j.read(), before)
        self.assertEqual(k.view().outbox[0].body, encode(create))

    def test_partition_retirement_survives_generation_switch(self):
        k, j = self.published()
        a, a1 = self.contexts["a"], self.contexts["a1"]
        self.code(k.observe(a, self.records["deleted"]), "keep_local_unlink_review")
        retired = k.view().head(self.profiles["p1"])
        local = k.view().locals[0]
        self.code(k.switch(a1), "quarantined")
        self.assertIsNone(k.view().head(self.profiles["p1"]))
        live = dict(json.loads(self.records["remote_edit"]), object_revision=3, event_sequence=3)
        for context in (a1, replace(a, generation=2)):
            if context != a1:
                self.code(k.switch(context), "quarantined")
            before, applies = k.view(), j.calls[1]
            self.code(k.observe(context, encode(live)), "requires_action")
            self.assertIs(k.view(), before)
            self.assertIsNone(k.view().head(self.profiles["p1"]))
            self.assertIs(k.view().candidates[1], retired)
            self.assertEqual(retired.raw, self.records["deleted"])
            self.assertEqual(retired.context, a)
            self.assertTrue(retired.deleted)
            self.assertIs(k.view().locals[0], local)
            self.assertEqual(local.accepted.raw, self.content["base"])
            self.assertEqual(j.calls[1], applies)
            self.code(k.select(context, "adopt", "local-retired", self.profiles["p1"]), "not_found")
            self.code(k.select(context, "edit", "local-one", self.bodies["gone"]), "not_found")
        self.code(k.next_request(), "requires_action")
        self.assertEqual(k.view().outbox[0].context, a)
        self.assertEqual(k.view().outbox[0].body, self.bodies["create"])
        self.assertEqual(k.view().outbox[0].status, "quarantined")

    def test_partition_immutable_reference_survives_generation_switch(self):
        k, j = self.published()
        a, a1 = self.contexts["a"], self.contexts["a1"]
        original = k.view().candidates[0]
        local = k.view().locals[0]
        self.code(k.switch(a1), "quarantined")
        before, applies = k.view(), j.calls[1]
        # A separately valid AS05 record reuses object/event/content generation 1
        # but proposes different exact content/hash after the local fence.
        changed = dict(json.loads(self.records["first"]), content_json=self.content["remote"].decode(),
                       content_hash=self.vectors["content"]["remote"]["hash"])
        self.code(k.observe(a1, encode(changed)), "requires_action")
        self.assertIs(k.view(), before)
        self.assertIsNone(k.view().head(self.profiles["p1"]))
        self.assertEqual(len(k.view().candidates), 1)
        self.assertIs(k.view().candidates[0], original)
        self.assertEqual(original.context, a)
        self.assertEqual((original.object_revision, original.event_sequence, original.content_revision), (1, 1, 1))
        self.assertEqual(original.content.raw, self.content["base"])
        self.assertEqual(original.content.sha256, self.vectors["content"]["base"]["hash"])
        self.assertIs(k.view().locals[0], local)
        self.assertEqual(j.calls[1], applies)

    def test_partition_newest_known_head_prevents_generation_regression(self):
        k, j = self.published()
        a, a1, a2 = self.contexts["a"], self.contexts["a1"], replace(self.contexts["a"], generation=2)
        self.code(k.observe(a, self.records["remote_edit"]), "pending_review")
        newest = k.view().candidates[1]
        self.code(k.switch(a1), "quarantined")
        before, applies = k.view(), j.calls[1]
        self.code(k.observe(a1, self.records["first"]), "unchanged")
        self.assertIs(k.view(), before)
        self.assertIsNone(k.view().head(self.profiles["p1"]))
        self.assertIs(k.view().candidates[1], newest)
        self.assertEqual(j.calls[1], applies)
        forward = dict(json.loads(self.records["remote_edit"]), object_revision=3, event_sequence=3,
                       content_revision=3, content_json=self.content["edit"].decode(),
                       content_hash=self.vectors["content"]["edit"]["hash"])
        forward_raw = encode(forward)
        self.code(k.observe(a1, forward_raw), "pending_review")
        current = k.view().head(self.profiles["p1"])
        self.assertEqual((current.context, current.object_revision, current.content_revision), (a1, 3, 3))
        self.assertEqual(current.raw, forward_raw)
        self.code(k.switch(a2), "quarantined")
        before, applies = k.view(), j.calls[1]
        for old in (self.records["first"], self.records["remote_edit"], forward_raw):
            self.code(k.observe(a2, old), "unchanged")
            self.assertIs(k.view(), before)
            self.assertIsNone(k.view().head(self.profiles["p1"]))
        self.assertEqual(len(k.view().candidates), 3)
        self.assertEqual([c.context for c in k.view().candidates], [a, a, a1])
        self.assertEqual([c.object_revision for c in k.view().candidates], [1, 2, 3])
        self.assertEqual(j.calls[1], applies)
        self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])

    def test_partition_exact_replay_and_forward_keep_original_provenance(self):
        k, j = self.published()
        a, a1 = self.contexts["a"], self.contexts["a1"]
        original, local = k.view().candidates[0], k.view().locals[0]
        self.code(k.switch(a1), "quarantined")
        before, applies = k.view(), j.calls[1]
        self.code(k.observe(a1, self.records["first"]), "unchanged")
        self.assertIs(k.view(), before)
        self.assertIsNone(k.view().head(self.profiles["p1"]))
        self.assertEqual(k.view().ordered_heads, ())
        self.assertEqual(j.calls[1], applies)
        self.code(k.observe(a1, self.records["remote_edit"]), "pending_review")
        head = k.view().head(self.profiles["p1"])
        self.assertEqual((head.context, head.object_revision, head.event_sequence, head.content_revision), (a1, 2, 2, 2))
        self.assertEqual(head.raw, self.records["remote_edit"])
        self.assertEqual(head.content.raw, self.content["remote"])
        self.assertEqual(head.content.sha256, self.vectors["content"]["remote"]["hash"])
        self.assertIs(k.view().candidates[0], original)
        self.assertEqual(original.context, a)
        self.assertEqual(original.raw, self.records["first"])
        self.assertIs(k.view().locals[0], local)
        self.assertEqual(local.accepted.raw, self.content["base"])
        before = k.view()
        self.code(k.observe(a1, self.records["remote_edit"]), "unchanged")
        self.assertIs(k.view(), before)
        self.assertEqual(k.view().links[0].context, a)
        self.assertEqual(k.view().links[0].review, "quarantined")
        self.code(k.select(a1, "edit", "local-one", self.bodies["edit"]), "not_found")
        self.code(k.acknowledge(a1, self.vectors["mutations"]["create"]["key"],
                               request_hash(self.bodies["create"]), self.records["first"]), "quarantined")
        self.code(k.observe(a, self.records["remote_edit"]), "quarantined")
        self.code(k.next_request(), "requires_action")
        self.assertEqual(k.view().outbox[0].body, self.bodies["create"])
        self.assertEqual(k.view().outbox[0].base_revision, 0)
        self.assertEqual(k.view().outbox[0].context, a)
        self.assertEqual(k.view().outbox[0].status, "quarantined")

    def test_partition_historical_content_object_and_event_constraints(self):
        a, a1 = self.contexts["a"], self.contexts["a1"]
        k, j = self.published()
        self.code(k.observe(a, self.records["remote_edit"]), "pending_review")
        self.code(k.switch(a1), "quarantined")
        before, applies = k.view(), j.calls[1]
        first, second = json.loads(self.records["first"]), json.loads(self.records["remote_edit"])
        cases = (
            dict(first, order_key=0),
            dict(first, content_json=self.content["remote"].decode(), content_hash=self.vectors["content"]["remote"]["hash"]),
            dict(first, profile_id=self.profiles["p2"]),
            dict(second, event_sequence=3, order_key=0),
            dict(second, object_revision=3, event_sequence=3, content_revision=1,
                 content_json=self.content["edit"].decode(), content_hash=self.vectors["content"]["edit"]["hash"]),
            dict(second, object_revision=3, event_sequence=1, content_revision=3),
        )
        for index, row in enumerate(cases):
            with self.subTest(case=index):
                self.code(k.observe(a1, encode(row)), "requires_action")
                self.assertIs(k.view(), before)
                self.assertIsNone(k.view().head(self.profiles["p1"]))
                self.assertIsNone(k.view().head(self.profiles["p2"]))
                self.assertEqual(j.calls[1], applies)
        self.assertEqual([c.context for c in k.view().candidates], [a, a])
        self.assertEqual([c.raw for c in k.view().candidates], [self.records["first"], self.records["remote_edit"]])
        self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])

    def test_partition_other_issuer_environment_account_allow_same_references(self):
        a = self.contexts["a"]
        changed = encode(dict(json.loads(self.records["first"]), content_json=self.content["remote"].decode(),
                              content_hash=self.vectors["content"]["remote"]["hash"]))
        for key in ("issuer1", "env1", "b1"):
            for raw, content_key in ((self.records["first"], "base"), (changed, "remote")):
                with self.subTest(partition=key, content=content_key):
                    k, _ = self.published()
                    self.code(k.observe(a, self.records["deleted"]), "keep_local_unlink_review")
                    prior, local = k.view().candidates, k.view().locals[0]
                    owner = self.contexts[key]
                    self.code(k.switch(owner), "quarantined")
                    self.assertIsNone(k.view().head(self.profiles["p1"]))
                    self.code(k.observe(owner, raw), "pending_review")
                    current = k.view().head(self.profiles["p1"])
                    self.assertEqual((current.object_revision, current.event_sequence, current.content_revision), (1, 1, 1))
                    self.assertEqual(current.profile_id, self.profiles["p1"])
                    self.assertEqual(current.context, owner)
                    self.assertFalse(current.deleted)
                    self.assertEqual(current.raw, raw)
                    self.assertEqual(current.content.raw, self.content[content_key])
                    self.assertEqual(current.content.sha256, self.vectors["content"][content_key]["hash"])
                    self.assertEqual(k.view().candidates[:2], prior)
                    self.assertEqual([c.context for c in prior], [a, a])
                    self.assertIs(k.view().locals[0], local)
                    self.assertEqual(local.accepted.raw, self.content["base"])
                    self.assertEqual(k.view().outbox[0].context, a)
                    self.assertEqual(k.view().outbox[0].body, self.bodies["create"])
                    self.assertEqual(k.view().outbox[0].status, "quarantined")
                    self.assertEqual(k.view().links[0].context, a)
                    self.assertEqual(k.view().links[0].review, "quarantined")
                    self.code(k.next_request(), "requires_action")

    def test_partition_return_uses_own_newest_head_not_other_owner_head(self):
        a, b, a2 = self.contexts["a"], self.contexts["b1"], replace(self.contexts["a"], generation=2)
        k, j = self.published()
        self.code(k.observe(a, self.records["remote_edit"]), "pending_review")
        local = k.view().locals[0]
        self.code(k.switch(b), "quarantined")
        other = encode(dict(json.loads(self.records["first"]), object_revision=10, event_sequence=10,
                            content_revision=10, content_json=self.content["edit"].decode(),
                            content_hash=self.vectors["content"]["edit"]["hash"]))
        self.code(k.observe(b, other), "pending_review")
        self.code(k.switch(a2), "quarantined")
        before, applies = k.view(), j.calls[1]
        self.code(k.observe(a2, self.records["first"]), "unchanged")
        self.assertIs(k.view(), before)
        self.assertIsNone(k.view().head(self.profiles["p1"]))
        self.assertEqual(j.calls[1], applies)
        # Source metadata forward in A's partition, not a rebase/accept action.
        forward = encode(dict(json.loads(self.records["remote_edit"]), object_revision=3, event_sequence=3, order_key=0))
        self.code(k.observe(a2, forward), "pending_review")
        head = k.view().head(self.profiles["p1"])
        self.assertEqual((head.context, head.object_revision, head.event_sequence, head.content_revision), (a2, 3, 3, 2))
        self.assertEqual(head.raw, forward)
        self.assertEqual(head.content.raw, self.content["remote"])
        self.assertEqual([c.context for c in k.view().candidates], [a, a, b, a2])
        self.assertEqual([c.object_revision for c in k.view().candidates], [1, 2, 10, 3])
        self.assertEqual(k.view().candidates[2].raw, other)
        self.assertIs(k.view().locals[0], local)
        self.assertEqual(local.accepted.raw, self.content["base"])
        self.assertEqual(k.view().outbox[0].context, a)
        self.assertEqual(k.view().outbox[0].status, "quarantined")
        self.assertEqual(k.view().ordered_heads, (head,))

    def reorder_request(self, *, base=1, order=0, key="psm_77777777777777777777777777777777", profile=None):
        # Synthetic INPUT builder only; receipt fields/expected outcomes below
        # are literal examples, never derived from the selected outbox/model.
        return encode({"schema": "healthmd.profile_sync", "schema_version": 1,
                       "operation": "reorder", "mutation_id": key, "base_revision": base,
                       "profile_id": profile or self.profiles["p1"], "order_key": order})

    def test_reorder_changed_receipt_preserves_order_content_and_accepted_marker(self):
        a = self.contexts["a"]
        k, j = self.published()
        before = k.view()
        self.code(k.observe(a, self.records["second"]), "pending_review")
        raw = b" \n" + self.reorder_request(order=0) + b" "
        self.code(k.select(a, "reorder", "local-one", raw), "queued")
        entry = k.view().outbox[-1]
        self.assertEqual((entry.operation, entry.choice, entry.base_revision, entry.desired_order, entry.context),
                         ("reorder", "reorder", 1, 0, a))
        self.assertIs(entry.base, before.candidates[0])
        self.assertIs(entry.content, entry.base.content)
        pending = k.next_request()
        self.assertEqual(pending.code, "pending")
        self.assertEqual((pending.request.body, pending.request.mutation_id, pending.request.request_hash),
                         (raw, "psm_77777777777777777777777777777777", request_hash(raw)))
        receipt = encode(dict(json.loads(self.records["first"]), object_revision=2, event_sequence=3, order_key=0))
        self.code(k.acknowledge(a, "psm_77777777777777777777777777777777", request_hash(raw), receipt), "pending_review")
        state = k.view()
        self.assertEqual(j.read().state, state)
        self.assertEqual((state.outbox[-1].status, state.outbox[-1].body, state.outbox[-1].acknowledgement.raw),
                         ("acknowledged", raw, receipt))
        self.assertEqual([(c.profile_id, c.order_key, c.object_revision, c.event_sequence, c.content_revision)
                          for c in state.ordered_heads],
                         [("psp_11111111111111111111111111111111", 0, 2, 3, 1),
                          ("psp_22222222222222222222222222222222", 2, 1, 2, 1)])
        self.assertEqual([(c.content.raw, c.content.sha256, c.context) for c in state.ordered_heads],
                         [(self.content["base"], "315912058e734b1613fb4b4775dbf8bd78944641151e8bd559eaa47e21e38750", a)] * 2)
        self.assertIs(state.locals[0], before.locals[0])
        self.assertEqual(state.locals[0].accepted.raw, self.content["base"])
        self.code(k.next_request(), "requires_action")
        with self.assertRaises(FrozenInstanceError):
            entry.desired_order = 1

    def test_reorder_same_order_no_op_retains_original_record_reference_and_readback(self):
        a = self.contexts["a"]
        for order, revision in ((0, 2), (2, 1), (9007199254740991, 2)):
            k, j = self.published()
            if order != 2:
                self.code(k.observe(a, encode(dict(json.loads(self.records["first"]),
                                                  object_revision=2, event_sequence=2, order_key=order))), "pending_review")
            before = k.view()
            raw = self.reorder_request(base=revision, order=order)
            self.code(k.select(a, "reorder", "local-one", raw), "queued")
            self.code(k.acknowledge(a, "psm_77777777777777777777777777777777", request_hash(raw), before.head(self.profiles["p1"]).raw), "pending_review")
            state, head = k.view(), k.view().head(self.profiles["p1"])
            self.assertEqual((head.object_revision, head.event_sequence, head.content_revision, head.order_key),
                             (revision, revision, 1, order))
            self.assertEqual(state.candidates, before.candidates)
            self.assertEqual((state.outbox[-1].status, state.outbox[-1].acknowledgement.raw), ("acknowledged", head.raw))
            self.assertIs(state.locals[0], before.locals[0])
            self.assertEqual((head.content.raw, state.locals[0].accepted.raw), (self.content["base"], self.content["base"]))
            self.assertEqual(head.content.sha256, "315912058e734b1613fb4b4775dbf8bd78944641151e8bd559eaa47e21e38750")
            self.assertEqual((state.ordered_heads, j.read().state), ((head,), state))

    def test_reorder_ties_zero_and_safe_max_preserve_separate_identical_names(self):
        a = self.contexts["a"]
        for order in (0, 9007199254740991):
            k, j = self.published()
            self.code(k.observe(a, encode(dict(json.loads(self.records["second"]), order_key=order))), "pending_review")
            raw = self.reorder_request(order=order)
            self.code(k.select(a, "reorder", "local-one", raw), "queued")
            receipt = encode(dict(json.loads(self.records["first"]), object_revision=2, event_sequence=3, order_key=order))
            self.code(k.acknowledge(a, "psm_77777777777777777777777777777777", request_hash(raw), receipt), "pending_review")
            self.assertEqual([(c.profile_id, c.order_key, c.content_revision) for c in k.view().ordered_heads],
                             [("psp_11111111111111111111111111111111", order, 1),
                              ("psp_22222222222222222222222222222222", order, 1)])
            self.assertEqual([c.content.raw for c in k.view().ordered_heads], [self.content["base"]] * 2)
            self.assertEqual(len(k.view().links), 1)  # no same-name merge/adopt
            self.assertEqual(j.read().state, k.view())

    def test_reorder_safe_counter_receipts_and_overflow_are_codec_bounded(self):
        a = self.contexts["a"]
        key, same_key, changed_key = ("psm_" + digit * 32 for digit in ("7", "6", "5"))
        k, j = self.published()
        high = encode(dict(json.loads(self.records["first"]), object_revision=9007199254740990,
                           event_sequence=9007199254740990))
        self.code(k.observe(a, high), "pending_review")
        raw = self.reorder_request(base=9007199254740990, order=0)
        self.code(k.select(a, "reorder", "local-one", raw), "queued")
        last = encode(dict(json.loads(self.records["first"]), object_revision=9007199254740991,
                           event_sequence=9007199254740991, order_key=0))
        self.code(k.acknowledge(a, key, request_hash(raw), last), "pending_review")
        head = k.view().head(self.profiles["p1"])
        self.assertEqual((head.object_revision, head.event_sequence, head.content_revision, head.order_key),
                         (9007199254740991, 9007199254740991, 1, 0))
        same = self.reorder_request(base=9007199254740991, order=0, key=same_key)
        self.code(k.select(a, "reorder", "local-one", same), "queued")
        self.code(k.acknowledge(a, same_key, request_hash(same), last), "pending_review")
        self.assertIs(k.view().head(self.profiles["p1"]), head)
        # Valid intent is not server capacity proof; actual codec denies overflow.
        changed = self.reorder_request(base=9007199254740991, order=2, key=changed_key)
        self.code(k.select(a, "reorder", "local-one", changed), "queued")
        overflow = encode(dict(json.loads(last), object_revision=9007199254740992,
                               event_sequence=9007199254740992, order_key=2))
        self.code(k.acknowledge(a, changed_key, request_hash(changed), overflow), "quarantined")
        self.assertIs(k.view().head(self.profiles["p1"]), head)
        self.assertEqual(k.view().outbox[-1].body, changed)
        self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])
        self.assertEqual(j.read().state, k.view())

    def test_reorder_exact_retry_key_mismatch_and_verified_snapshot_restart(self):
        a, key = self.contexts["a"], "psm_77777777777777777777777777777777"
        k, j = self.published()
        raw = b"\n" + self.reorder_request() + b" "
        self.code(k.select(a, "reorder", "local-one", raw), "queued")
        before, applies = k.view(), j.calls[1]
        self.code(k.select(a, "reorder", "local-one", raw), "unchanged")
        for changed in (raw + b" ", self.reorder_request(order=1)):
            self.code(k.select(a, "reorder", "local-one", changed), "idempotency_mismatch")
        self.code(k.select(a, "reorder", "local-two", raw), "requires_action")
        self.assertEqual((k.view(), j.calls[1]), (before, applies))
        saved = j.read()
        restart, rj = self.make(journal=MemoryJournal(a, record=saved))
        for _ in range(2):
            result = restart.next_request()
            self.assertEqual(result.code, "pending")
            self.assertEqual((result.request.body, result.request.mutation_id, result.request.request_hash, result.request.context),
                             (raw, key, request_hash(raw), a))
        self.assertEqual((rj.read(), rj.calls[1]), (saved, 0))
        receipt = encode(dict(json.loads(self.records["first"]), object_revision=2, event_sequence=2, order_key=0))
        self.code(restart.acknowledge(a, key, request_hash(raw), receipt), "pending_review")
        saved = rj.read()
        again, aj = self.make(journal=MemoryJournal(a, record=saved))
        self.code(again.acknowledge(a, key, request_hash(raw), receipt), "unchanged")
        self.code(again.next_request(), "requires_action")
        self.assertEqual((aj.read(), aj.calls[1]), (saved, 0))

    def test_reorder_bad_requests_and_scope_refuse_before_journal_apply(self):
        a = self.contexts["a"]
        k, j = self.published()
        raw = self.reorder_request()
        value = json.loads(raw)
        patches = ({"order_key": True}, {"order_key": None}, {"order_key": "0"}, {"order_key": [0]},
                   {"order_key": {}}, {"order_key": -1}, {"order_key": 9007199254740992},
                   {"base_revision": 0}, {"base_revision": False}, {"base_revision": 1.0},
                   {"base_revision": "1"}, {"base_revision": 9007199254740992},
                   {"mutation_id": "psm_bad"}, {"profile_id": "local-one"},
                   {"schema_version": 2}, {"operation": []}, {"operation": {}}, {"extra": None})
        malformed = [encode(dict(value, **p)) for p in patches]
        malformed += [encode({f: v for f, v in value.items() if f != "order_key"}),
                      raw.replace(b'"order_key":0', b'"order_key":-0'),
                      raw.replace(b'"order_key":0', b'"order_key":0e0'),
                      raw.replace(b'"order_key":0', b'"order_key":0,"order_key":0'),
                      b"\xff", b"\xef\xbb\xbf" + raw, raw + b"{}", b"[]", None, raw.decode(), bytearray(raw)]
        before, calls = k.view(), j.calls
        for index, bad in enumerate(malformed):
            with self.subTest(malformed=index):
                self.code(k.select(a, "reorder", "local-one", bad), "invalid")
                self.assertIs(k.view(), before)
                self.assertEqual(j.calls, calls)
        self.code(k.select(a, "reorder", "local-one", raw + b" " * model.MAX_ITEM_BYTES), "quota_exceeded")
        for body in (self.bodies["create"], self.bodies["edit"], self.bodies["delete"]):
            self.code(k.select(a, "reorder", "local-one", body), "requires_action")
        self.code(k.select(a, "reorder", "local-one", self.reorder_request(profile=self.profiles["p2"])), "not_found")
        self.code(k.select(a, "reorder", "local-one", self.reorder_request(base=2)), "requires_action")
        self.code(k.select(a, "reorder", "local-missing", raw), "not_found")
        self.code(k.select(a, "reorder", None, raw), "requires_action")
        for scope in ("a1", "b1", "env1", "issuer1"):
            self.code(k.select(self.contexts[scope], "reorder", "local-one", raw), "quarantined")
        self.assertIs(k.view(), before)
        self.assertEqual(j.calls, calls)
        self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])

    def test_reorder_unlinked_deleted_dirty_and_conflict_preserve_prior_work(self):
        a = self.contexts["a"]
        k, j = self.seeded()
        self.code(k.observe(a, self.records["first"]), "pending_review")
        before, calls = k.view(), j.calls
        self.code(k.select(a, "reorder", "local-one", self.reorder_request()), "not_found")
        self.assertEqual((k.view(), j.calls), (before, calls))
        for choice, body in (("edit", self.bodies["edit"]), ("delete", self.bodies["delete"]), ("reorder", self.reorder_request())):
            for remote in ("remote_edit", "deleted"):
                k, j = self.published()
                self.code(k.select(a, choice, "local-one", body), "queued")
                original = k.view().outbox[-1]
                before, applies = k.view(), j.calls[1]
                self.code(k.select(a, "reorder", "local-one", self.reorder_request(key="psm_66666666666666666666666666666666")), "requires_action")
                self.assertEqual((k.view(), j.calls[1]), (before, applies))
                self.code(k.observe(a, self.records[remote]), "edit_delete_conflict" if remote == "deleted" else "edit_edit_conflict")
                before, applies = k.view(), j.calls[1]
                self.code(k.select(a, "reorder", "local-one", self.reorder_request(base=2, key="psm_66666666666666666666666666666666")),
                          "gone" if remote == "deleted" else "requires_action")
                self.code(k.acknowledge(a, original.mutation_id, original.request_hash, self.records["first"]), "requires_action")
                self.code(k.next_request(), "requires_action")
                self.assertEqual((k.view(), j.calls[1]), (before, applies))
                self.assertEqual((k.view().outbox[-1].body, k.view().outbox[-1].base, k.view().outbox[-1].status),
                                 (body, original.base, "conflict"))
                self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])

    def test_reorder_explicit_adopted_link_remains_portable_only(self):
        a = self.contexts["a"]
        k, j = self.make()
        self.code(k.observe(a, self.records["first"]), "pending_review")
        self.code(k.select(a, "adopt", "local-new", self.profiles["p1"]), "pending_review")
        raw = self.reorder_request()
        self.code(k.select(a, "reorder", "local-new", raw), "queued")
        receipt = encode(dict(json.loads(self.records["first"]), object_revision=2, event_sequence=2, order_key=0))
        self.code(k.acknowledge(a, "psm_77777777777777777777777777777777", request_hash(raw), receipt), "pending_review")
        self.assertEqual((k.view().locals, k.view().head(self.profiles["p1"]).order_key), ((), 0))
        self.assertEqual(j.read().state, k.view())  # no native row/accepted marker

    def test_reorder_wrong_receipts_never_replace_base_content_or_accepted_marker(self):
        a = self.contexts["a"]
        changed = dict(json.loads(self.records["first"]), object_revision=2, event_sequence=2, order_key=0)
        bad_changed = [dict(changed, **p) for p in (
            {"profile_id": self.profiles["p2"]}, {"object_revision": 1}, {"object_revision": 3},
            {"event_sequence": 1}, {"order_key": 1}, {"order_key": 2}, {"content_revision": 2},
            {"content_json": self.content["edit"].decode(), "content_hash": self.vectors["content"]["edit"]["hash"]},
            {"content_hash": "0" * 64}, {"schema_version": 2}, {"order_key": 9007199254740992},
            {"object_revision": 9007199254740992}, {"event_sequence": 9007199254740992},
            {"event_sequence": 2.0}, {"deleted": "false"}, {"extra": None})]
        no_op = json.loads(self.records["first"])
        bad_no_op = [dict(no_op, **p) for p in (
            {"object_revision": 2, "event_sequence": 2}, {"event_sequence": 2}, {"order_key": 0},
            {"object_revision": 2, "content_revision": 2},
            {"content_json": self.content["remote"].decode(), "content_hash": self.vectors["content"]["remote"]["hash"]})]
        for order, rows in ((0, bad_changed), (2, bad_no_op)):
            malformed = [encode(row) for row in rows] + [self.records["deleted"], b"\xff", None,
                encode({"schema": "healthmd.profile_sync", "schema_version": 1, "result": "conflict"})]
            for index, receipt in enumerate(malformed):
                with self.subTest(order=order, receipt=index):
                    k, j = self.published()
                    raw = self.reorder_request(order=order)
                    self.code(k.select(a, "reorder", "local-one", raw), "queued")
                    before = k.view()
                    self.code(k.acknowledge(a, "psm_77777777777777777777777777777777", request_hash(raw), receipt), "quarantined")
                    state = k.view()
                    self.assertEqual((state.candidates, state.links, state.locals), (before.candidates, before.links, before.locals))
                    entry = state.outbox[-1]
                    self.assertEqual((entry.status, entry.acknowledgement, entry.body), ("quarantined", None, raw))
                    self.assertEqual(state.locals[0].accepted.raw, self.content["base"])
                    self.assertEqual(j.read().state, state)
                    self.code(k.next_request(), "requires_action")
        # Capacity refusal retains the pending original intent.
        k, j = self.published()
        raw = self.reorder_request()
        self.code(k.select(a, "reorder", "local-one", raw), "queued")
        before, applies = k.view(), j.calls[1]
        self.code(k.acknowledge(a, "psm_77777777777777777777777777777777", request_hash(raw),
                               encode(changed) + b" " * model.MAX_ITEM_BYTES), "quota_exceeded")
        self.assertIs(k.view(), before)
        self.assertEqual(j.calls[1], applies)
        self.assertEqual(k.next_request().request.body, raw)

    def test_reorder_receipt_owner_hash_and_generation_fences_retain_original_intent(self):
        a = self.contexts["a"]
        raw = self.reorder_request()
        key = "psm_77777777777777777777777777777777"
        receipt = encode(dict(json.loads(self.records["first"]), object_revision=2, event_sequence=2, order_key=0))
        for owner, digest in [(self.contexts[s], request_hash(raw)) for s in ("a1", "b1", "env1", "issuer1")] + [(a, "0" * 64)]:
            k, _ = self.published()
            self.code(k.select(a, "reorder", "local-one", raw), "queued")
            self.code(k.acknowledge(owner, key, digest, receipt), "quarantined")
            self.assertEqual((k.view().head(self.profiles["p1"]).raw, k.view().outbox[-1].body), (self.records["first"], raw))
        k, j = self.published()
        self.code(k.select(a, "reorder", "local-one", raw), "queued")
        original = k.view().outbox[-1]
        self.code(k.acknowledge(a, "psm_66666666666666666666666666666666", request_hash(raw), receipt), "not_found")
        self.code(k.switch(self.contexts["a1"]), "quarantined")
        self.code(k.acknowledge(a, key, request_hash(raw), receipt), "quarantined")
        self.code(k.observe(self.contexts["a1"], receipt), "pending_review")
        self.code(k.select(self.contexts["a1"], "reorder", "local-one", raw), "quarantined")
        self.code(k.select(self.contexts["a1"], "reorder", "local-one",
                           self.reorder_request(base=2, key="psm_66666666666666666666666666666666")), "not_found")
        self.code(k.next_request(), "requires_action")
        retained = k.view().outbox[-1]
        self.assertEqual((retained.context, retained.body, retained.request_hash, retained.base,
                          retained.base_revision, retained.desired_order, retained.status),
                         (a, raw, request_hash(raw), original.base, 1, 0, "quarantined"))
        self.assertEqual(k.view().locals[0].accepted.raw, self.content["base"])
        self.assertEqual(j.read().state, k.view())

    def test_reorder_journal_enqueue_and_receipt_faults_keep_proposal_not_guessed_success(self):
        a = self.contexts["a"]
        raw, key = self.reorder_request(), "psm_77777777777777777777777777777777"
        receipt = encode(dict(json.loads(self.records["first"]), object_revision=2, event_sequence=2, order_key=0))
        for phase in ("enqueue", "receipt"):
            for fault in FaultJournal.FAULTS:
                with self.subTest(phase=phase, fault=fault):
                    j = FaultJournal(a)
                    k, _ = self.published(journal=j)
                    if phase == "receipt":
                        self.code(k.select(a, "reorder", "local-one", raw), "queued")
                    before, applies = k.view(), j.calls[1]
                    j.arm(fault, replacement=self.contexts["a1"])
                    result = (k.select(a, "reorder", "local-one", raw) if phase == "enqueue" else
                              k.acknowledge(a, key, request_hash(raw), receipt))
                    success = "queued" if phase == "enqueue" else "pending_review"
                    self.code(result, success if fault == "lost_response" else
                              "fenced" if fault == "stale_owner" else "verification_pending")
                    if fault != "lost_response":
                        self.assertIs(k.view(), before)
                    if fault == "unreadable":
                        with self.assertRaises(JournalError):
                            j.read()
                        j.make_readable()
                        self.code(k.verify(), success)
                    actual = j.read()
                    desired = actual.state if actual.pending is None else actual.pending.desired
                    entry = desired.outbox[-1]
                    self.assertEqual((entry.body, entry.mutation_id, entry.request_hash, entry.context,
                                      entry.base_revision, entry.desired_order, entry.status),
                                     (raw, key, request_hash(raw), a, 1, 0, "pending" if phase == "enqueue" else "acknowledged"))
                    self.assertEqual((entry.base.raw, entry.content.raw), (self.records["first"], self.content["base"]))
                    self.assertEqual(desired.locals, before.locals)
                    if phase == "receipt":
                        self.assertEqual(entry.acknowledgement.raw, receipt)
                    expected = ("fenced" if fault == "stale_owner" else "verification_pending") if actual.pending else "unchanged"
                    if actual.pending:
                        self.assertEqual(actual.pending.before, before)
                        self.assertEqual(actual.state.outbox, before.outbox)
                        if fault == "partial":
                            self.assertEqual(actual.state.candidates, desired.candidates)
                    restarted, rj = self.make(journal=MemoryJournal(a, record=actual))
                    self.code(restarted.verify(), expected)
                    self.assertEqual(restarted.view(), before if actual.pending else desired)
                    pending = restarted.next_request()
                    self.assertEqual(pending.code, expected if actual.pending else "pending" if phase == "enqueue" else "requires_action")
                    if pending.request:
                        self.assertEqual(pending.request.body, raw)
                    self.assertEqual(restarted.view().locals[0].accepted.raw, self.content["base"])
                    self.assertEqual((rj.calls[1], j.calls[1]), (0, applies + 1))  # no repair/rollback

    def test_reorder_real_outbox_bound_and_competing_cas_do_not_replace_prior_work(self):
        a = self.contexts["a"]
        k, j = self.make()
        self.code(k.local(a, "local-one", self.content["current"]), "local_preserved")
        create = encode(dict(json.loads(self.bodies["create"]), content_json=self.content["current"].decode(),
                             content_hash=self.vectors["content"]["current"]["hash"]))
        row = encode(dict(json.loads(self.records["first"]), content_json=self.content["current"].decode(),
                          content_hash=self.vectors["content"]["current"]["hash"]))
        self.code(k.select(a, "publish", "local-one", create), "queued")
        self.code(k.acknowledge(a, "psm_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", request_hash(create), row), "pending_review")
        for i in range(7):
            key = "psm_" + f"{i:032x}"
            raw = self.reorder_request(order=2, key=key)
            self.code(k.select(a, "reorder", "local-one", raw), "queued")
            # Retained non-success has no receipt payload, isolating count from
            # byte capacity. Seven successful receipts exceeded the real byte
            # bound first (both failures/diagnostic retained), not a kernel bug.
            self.code(k.acknowledge(a, key, "0" * 64, row), "quarantined")
            self.assertEqual(k.view().outbox[-1].body, raw)
            self.assertEqual(k.view().outbox[-1].base.raw, row)
            self.assertEqual(k.view().outbox[-1].desired_order, 2)
        self.assertEqual(len(k.view().outbox), 8)
        self.assertEqual([e.status for e in k.view().outbox], ["acknowledged"] + ["quarantined"] * 7)
        before, applies = j.read(), j.calls[1]
        self.code(k.select(a, "reorder", "local-one", self.reorder_request()), "quota_exceeded")
        self.assertEqual(j.read(), before)
        self.assertEqual(j.calls[1], applies)
        self.assertEqual(k.view().locals[0].accepted.raw, self.content["current"])
        # Deterministic actual CAS loser, not thread/OS durability proof.
        winner, wj = self.published()
        loser, _ = self.make(journal=wj)
        prior = loser.view()
        first, second = self.reorder_request(), self.reorder_request(order=1, key="psm_" + "6" * 32)
        self.code(winner.select(a, "reorder", "local-one", first), "queued")
        self.code(loser.select(a, "reorder", "local-one", second), "verification_pending")
        self.code(loser.next_request(), "verification_pending")
        self.assertIs(loser.view(), prior)
        actual = wj.read()
        self.assertEqual((actual.pending, actual.state.outbox[-1].body, actual.state.outbox[-1].desired_order), (None, first, 0))

    def test_step_capacity_eligibility(self):
        for n, wanted in ((29, "pending"), (30, "quota_exceeded")):
            k, j = self.seeded()
            for i in range(1, n + 1):
                c = replace(self.contexts["a"], generation=i)
                self.code(k.switch(c), "quarantined")
            b = self.bodies["create"]
            self.code(k.select(c, "publish", "local-one", b), "queued")
            saved = j.read()
            peer, pj = self.make(context=c, journal=MemoryJournal(c, record=saved))
            for u in (k, peer):
                r = u.next_request()
                self.assertEqual((r.code, r.request is None, u.view()), (wanted, n == 30, saved.state))
            e = saved.state.outbox[0]
            self.assertEqual((e.body, e.mutation_id, e.request_hash, e.base_revision, e.context),
                             (b, "psm_" + "a" * 32, request_hash(b), 0, c))
            self.assertEqual(saved.state.locals[0].accepted.raw, self.content["base"])
            self.assertEqual((j.read(), pj.read()), (saved, saved))

    def test_byte_capacity_eligibility(self):
        for tail, denial, wanted, size in ((5311, "quarantined", "requires_action", 131019),
                                          (5331, "quota_exceeded", "quota_exceeded", 131059)):
            c = self.contexts["env1"]
            k, j = self.make(context=c)
            b = encode(dict(json.loads(self.bodies["create"]), mutation_id="psm_" + "d" * 32))
            self.code(k.local(c, "local-byte", self.content["base"]), "local_preserved")
            self.code(k.select(c, "publish", "local-byte", b), "queued")
            r = k.next_request().request  # actual capture BEFORE public byte filling
            self.assertEqual((r.body, r.mutation_id, r.request_hash, r.context),
                             (b, "psm_" + "d" * 32, request_hash(b), c))
            inputs = [self.content["base"]]
            for i, n in enumerate((26000, 26000, tail)):
                raw = self.content["current"] + b" " * (n - len(self.content["current"]))
                inputs.append(raw)
                self.code(k.local(c, f"local-fill-{i}", raw), "local_preserved")
            saved, applies = j.read(), j.calls[1]
            s = saved.state
            self.assertEqual((saved.serial, len(s.history), len(s.locals), len(s.links),
                              len(s.candidates), len(s.outbox)), (5, 5, 4, 0, 0, 1))
            self.assertEqual(model.logical_bytes(s), size)  # independently worked input charges
            self.code(k.acknowledge(c, r.mutation_id, "0" * 64, self.records["first"]), denial)
            after = j.read()
            if tail == 5331:
                self.assertEqual((after, k.view(), j.calls[1]), (saved, s, applies))
            else:
                self.assertEqual((after.serial, after.state.outbox[0].status), (6, "quarantined"))
            e = after.state.outbox[0]
            self.assertEqual((e.body, e.mutation_id, e.request_hash, e.base_revision, e.context),
                             (b, "psm_" + "d" * 32, request_hash(b), 0, c))
            self.assertEqual([l.accepted.raw for l in after.state.locals], inputs)
            self.assertEqual([l.content.raw for l in after.state.locals], inputs)
            peer, pj = self.make(context=c, journal=MemoryJournal(c, record=after))
            for u in (k, peer):
                self.code(u.next_request(), wanted)  # literal fail-closed rule, no Request
                self.assertEqual(u.view(), after.state)
            self.assertEqual((j.read(), pj.read()), (after, after))

    def test_all_test_filesystem_operations_are_read_only(self):
        original = io.open
        def reads_only(file, mode="r", *args, **kwargs):
            if any(c in mode for c in ("w", "a", "+", "x")):
                raise AssertionError("unexpected filesystem persistence")
            return original(file, mode, *args, **kwargs)
        with patch("io.open", side_effect=reads_only):
            k, j = self.published()
            saved = j.read()
            restarted, _ = self.make(journal=MemoryJournal(self.contexts["a"], record=saved))
            self.assertEqual(restarted.view(), k.view())
        for file in (HERE / "model.py", HERE / "journal.py"):
            tree = ast.parse(file.read_bytes())
            imports = {n.module for n in ast.walk(tree) if isinstance(n, ast.ImportFrom)}
            imports |= {a.name for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
            self.assertLessEqual(imports, {"__future__", "dataclasses", "hashlib", "importlib.util", "pathlib", "re", "sys", "threading", "typing", "journal"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="AS07 bounded SOURCE tests, read-only actual AS05 codec")
    parser.add_argument("--codec-path", type=Path, default=CODEC_PATH)
    options, rest = parser.parse_known_args()
    CODEC_PATH = options.codec_path
    unittest.main(argv=[__file__] + rest, verbosity=2)
