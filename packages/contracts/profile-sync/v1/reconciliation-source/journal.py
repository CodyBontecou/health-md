"""SOURCE ONLY: exclusive in-memory journal and fault adapter, no durable IO.

The interface is read()/apply(expected, owner, state). A returned apply value is
never commit evidence; callers compare exact readback. Faults retain the proposal
in the record, including a no-op *state apply*. They do not simulate OS crashes.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from threading import Lock
from typing import Protocol


class JournalError(Exception):
    def __init__(self):
        super().__init__("verification_pending")


@dataclass(frozen=True, repr=False)
class Proposal:
    before: object
    desired: object


@dataclass(frozen=True, repr=False)
class Record:
    serial: int
    fence: object
    state: object = None
    pending: Proposal | None = None


class Journal(Protocol):
    def read(self) -> Record: ...
    def apply(self, expected: Record, owner: object, state: object) -> None: ...


class MemoryJournal:
    """One lock protects expected-record comparison, owner check and mutation.

    A restart accepts only an exact Record from read(), not JSON/file recovery.
    The SOURCE kernel bounds all states before entering apply(). This adapter is
    internal test infrastructure, not a hostile-input/persistent adapter.
    """
    def __init__(self, owner, *, record=None):
        self._lock = Lock()
        self._record = Record(0, owner) if record is None else record
        self._reads = self._applies = 0

    @property
    def calls(self):
        with self._lock:
            return (self._reads, self._applies)

    def read(self):
        with self._lock:
            self._reads += 1
            return self._record

    def apply(self, expected, owner, state):
        with self._lock:
            self._applies += 1
            if self._record != expected or self._record.fence != owner:
                raise JournalError()
            self._write(expected, state)

    def _write(self, expected, state):
        self._record = Record(expected.serial + 1, state.context, state)


class FaultJournal(MemoryJournal):
    """Same interface; a single armed deterministic fault at actual mutation.

    no_op: journal retains intent, but does not apply state.
    partial: applies desired locals/candidates but retains the prior outbox.
    lost_response: commits, then throws; readable exact readback can verify it.
    unreadable: commits, then read() fails until explicitly made readable.
    stale_owner: changes the journal fence before the actual owner check/write;
                 retains both user state and the uncommitted proposal.
    """
    FAULTS = ("no_op", "partial", "lost_response", "unreadable", "stale_owner")

    def __init__(self, owner, *, record=None):
        super().__init__(owner, record=record)
        self._fault = None
        self._replacement = None
        self._readable = True

    def arm(self, fault, *, replacement=None):
        if fault not in self.FAULTS:
            raise ValueError("invalid")
        with self._lock:
            self._fault, self._replacement = fault, replacement

    def make_readable(self):
        with self._lock:
            self._readable = True

    def read(self):
        with self._lock:
            self._reads += 1
            if not self._readable:
                raise JournalError()
            return self._record

    def _write(self, expected, state):
        fault, self._fault = self._fault, None
        proposal = Proposal(expected.state, state)
        if fault == "stale_owner":
            if self._replacement is None or self._replacement == expected.fence:
                raise JournalError()
            self._record = Record(expected.serial + 1, self._replacement,
                                  expected.state, proposal)
            raise JournalError()
        if fault == "no_op":
            self._record = Record(expected.serial + 1, expected.fence,
                                  expected.state, proposal)
            return
        if fault == "partial":
            old_outbox = () if expected.state is None else expected.state.outbox
            partial = replace(state, outbox=old_outbox)
            self._record = Record(expected.serial + 1, expected.fence, partial, proposal)
            return
        super()._write(expected, state)
        if fault == "unreadable":
            self._readable = False
        if fault in ("lost_response", "unreadable"):
            raise JournalError()
