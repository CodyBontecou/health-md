# Packaged interoperability fixture mirrors

These JSON files are retained inside the independently published `healthmd-protocol` crate so its source archive and integration tests remain self-contained.

Canonical assets and provenance live under:

- [`packages/contracts/direct-protocol/v1/fixtures/swift-reference.json`](../../../../../../packages/contracts/direct-protocol/v1/fixtures/swift-reference.json)
- [`packages/contracts/direct-protocol/v2/fixtures/interop.json`](../../../../../../packages/contracts/direct-protocol/v2/fixtures/interop.json)

Run `python3 packages/contracts/validate.py` from the repository root after any fixture change. Validation requires these mirrors to remain byte-identical to their canonical files. Do not regenerate a reference vector merely to silence a consumer failure.
