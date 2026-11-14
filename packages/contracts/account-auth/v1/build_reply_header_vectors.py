"""Deterministic synthetic reply-header vectors; no native/HTTP qualification.

Golden validity is authored independently of reply_headers.py. The policy digest
pins reviewed source choices, not a consumer's verdict or production approval.
"""

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "fixtures/native-reply-header-vectors.json"


def build_vectors():
    policy = json.loads((HERE / "source-policy.json").read_text())["native_reply_headers"]
    encoded = json.dumps(policy, sort_keys=True, separators=(",", ":")).encode()
    bare = [["Content-Type", "application/json"], ["Cache-Control", "no-store"], ["Referrer-Policy", "no-referrer"]]
    utf8 = [["Content-Type", "application/json; charset=utf-8"], *bare[1:]]
    cases = []

    def add(id_, pairs, valid):
        cases.append({"id": id_, "pairs": pairs, "valid": valid})

    add("bare-json", bare, True)
    add("cloud-utf8-hardening", [*utf8,
        ["Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"],
        ["X-Frame-Options", "DENY"], ["X-Content-Type-Options", "nosniff"]], True)
    add("ascii-case-required", [[key.swapcase(), value] for key, value in bare], True)
    add("preserve-safe-extra", [*bare, ["X-Source-Label", "synthetic  unmodified"]], True)
    add("empty-safe-extra", [*bare, ["X-Empty", ""]], True)
    add("name-max-64", [*bare, ["H" + "a" * 63, "x"]], True)
    add("name-over-65", [*bare, ["H" + "a" * 64, "x"]], False)
    add("value-max-1024", [*bare, ["X-Pad", "A" * 1024]], True)
    add("value-over-1025", [*bare, ["X-Pad", "A" * 1025]], False)
    add("count-max-16", [*bare, *[[f"X-{i}", "x"] for i in range(13)]], True)
    add("count-over-17", [*bare, *[[f"X-{i}", "x"] for i in range(14)]], False)

    def aggregate(size):
        pairs = [list(pair) for pair in utf8]
        remaining = size - sum(len(key) + len(value) for key, value in pairs)
        while remaining:
            key = f"X-Pad-{len(pairs)}"
            assert remaining >= len(key)
            value = "A" * min(1024, remaining - len(key))
            pairs.append([key, value])
            remaining -= len(key) + len(value)
        assert len(pairs) <= 16
        return pairs

    add("aggregate-max-4096", aggregate(4096), True)
    add("aggregate-over-4097", aggregate(4097), False)
    add("duplicate-identical-raw", [*bare, list(bare[0])], False)
    add("duplicate-folded-raw", [*bare, ["cOnTeNt-TyPe", "application/json"]], False)
    add("duplicate-safe-extra", [*bare, ["X-Extra", "a"], ["x-extra", "b"]], False)
    for name in ("Cookie", "Set-Cookie", "Authorization", "Proxy-Authorization"):
        add("credential-" + name.lower(), [*bare, [name, "synthetic-no-authority"]], False)
        add("credential-upper-" + name.lower(), [*bare, [name.upper(), "synthetic-no-authority"]], False)
    for index in range(3):
        add("required-missing-" + str(index), [pair for i, pair in enumerate(bare) if i != index], False)
        add("required-empty-" + str(index), [[key, "" if i == index else value] for i, (key, value) in enumerate(bare)], False)
        add("required-surrounding-space-" + str(index), [[key, " " + value if i == index else value] for i, (key, value) in enumerate(bare)], False)
    for index, value in enumerate(("text/html", "application/json; charset=UTF-8", "application/json;charset=utf-8", "APPLICATION/JSON")):
        add("media-type-unsupported-" + str(index), [["Content-Type", value], *bare[1:]], False)
    add("cache-control-not-exact", [bare[0], ["Cache-Control", "private, no-store"], bare[2]], False)
    add("referrer-policy-not-exact", [*bare[:2], ["Referrer-Policy", "same-origin"]], False)
    for point in [*range(32), 127, 133, 160, 8232, 8233, 65279]:
        add(f"unsafe-value-u{point:04x}", [*bare, ["X-Extra", "before" + chr(point) + "after"]], False)
    for index, key in enumerate(("", " Content-Type", "Content-Type ", "X:Extra", "X_Extra", "X.Extra", "X\nExtra", "X\x00Extra", "X-\u00e9")):
        add("name-unsupported-" + str(index), [*bare, [key, "x"]], False)
    for id_, malformed in (("input-map", dict(bare)), ("input-null", None), ("input-string", "synthetic"),
            ("pair-map", [*bare, {"name": "X", "value": "x"}]), ("pair-short", [*bare, ["X"]]),
            ("pair-long", [*bare, ["X", "x", "extra"]]), ("pair-null", [*bare, None]),
            ("name-boolean", [*bare, [True, "x"]]), ("value-boolean", [*bare, ["X", True]]),
            ("name-number", [*bare, [1, "x"]]), ("value-number", [*bare, ["X", 1]]),
            ("name-null", [*bare, [None, "x"]]), ("value-null", [*bare, ["X", None]])):
        add(id_, malformed, False)
    return {
        "schema": "healthmd.account_auth.native_reply_header_vectors",
        "schema_version": 1,
        "synthetic_only": True,
        "status": "reviewed_source_profile_not_native_or_http_qualification",
        "native_consumers_qualified": False,
        "grants_authority": False,
        "policy_sha256": hashlib.sha256(encoded).hexdigest(),
        "operations": ["code_exchange", "refresh", "revoke"],
        "cases": cases,
    }


if __name__ == "__main__":
    data = build_vectors()
    OUT.write_text(json.dumps(data, indent=2, ensure_ascii=True) + "\n")
    print(f"Synthetic header vectors: {len(data['cases'])}; native/HTTP qualified=false")
