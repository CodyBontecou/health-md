"""Synthetic source-profile reference only; NOT HTTP, TLS or account authority.

The input is already a lossless sequence of decoded header pairs. A real adapter
must independently bound the raw stream, retain duplicates, correlate the request,
reject redirects/cookies/retries and validate status/body/clock/custody. No native
consumer or network/storage port is implemented or qualified by this module.
"""

from dataclasses import dataclass, field
import re
from typing import Optional, Tuple

MAX_PAIRS = 16
MAX_NAME_BYTES = 64
MAX_VALUE_BYTES = 1024
MAX_PAIR_BYTES = 4096  # Sum of name+value bytes; NOT HTTP framing/stream bytes.
NAME = re.compile(r"[A-Za-z0-9-]{1,64}")
FORBIDDEN = frozenset(("cookie", "set-cookie", "authorization", "proxy-authorization"))
REQUIRED = (
    ("content-type", ("application/json", "application/json; charset=utf-8")),
    ("cache-control", ("no-store",)),
    ("referrer-policy", ("no-referrer",)),
)


@dataclass(frozen=True, repr=False)
class ReplyHeaders:
    """Immutable accepted original pairs; this object grants NO authority."""

    pairs: Tuple[Tuple[str, str], ...] = field(repr=False)

    def get(self, name: str) -> Optional[str]:
        if type(name) is not str or not NAME.fullmatch(name):
            return None
        folded = name.lower()  # ASCII-only names; never normalize values/pairs.
        return next((value for key, value in self.pairs if key.lower() == folded), None)

    def __repr__(self) -> str:
        return "ReplyHeaders(<redacted>, source-only, no authority)"

    __str__ = __repr__


def invalid():
    # Unknown safe fields may still be sensitive; never reflect names/values.
    raise ValueError("invalid source reply headers")


def parse_reply_headers(pairs) -> ReplyHeaders:
    """Check bounded raw pair DTOs BEFORE any lossy map/case-fold conversion.

    Exact list/tuple and string types deny generators, maps and coercion. This is
    a finite first-party subset, not a general RFC HTTP-header implementation.
    Printable ASCII values may be empty only on non-required fields. Safe unknown
    headers (including CSP/frame/nosniff) are allowed but never acted upon here.
    """
    if type(pairs) not in (list, tuple) or len(pairs) > MAX_PAIRS:
        invalid()
    accepted = []
    values = {}
    total = 0
    for pair in pairs:
        if type(pair) not in (list, tuple) or len(pair) != 2:
            invalid()
        name, value = pair
        if type(name) is not str or type(value) is not str:
            invalid()
        # Length-first bounds; ASCII checks make codepoints == UTF-8 bytes.
        if not 1 <= len(name) <= MAX_NAME_BYTES or len(value) > MAX_VALUE_BYTES:
            invalid()
        if not NAME.fullmatch(name) or any(not 0x20 <= ord(ch) <= 0x7E for ch in value):
            invalid()
        total += len(name) + len(value)
        if total > MAX_PAIR_BYTES:
            invalid()
        folded = name.lower()
        if folded in values or folded in FORBIDDEN:
            invalid()
        values[folded] = value
        accepted.append((name, value))
    if any(values.get(name) not in allowed for name, allowed in REQUIRED):
        invalid()
    return ReplyHeaders(tuple(accepted))
