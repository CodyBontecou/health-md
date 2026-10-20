# Temporary Askama tooling parser patch

This is the published `askama_derive` 0.16.0 source, copied from its checksum-verified Cargo archive.
The upstream source revision, original file hashes, omitted cache/lock metadata, and archive checksum
are recorded in `HEALTHMD-PROVENANCE.json`. The upstream MIT/Apache licenses remain included.
`Cargo.toml.orig` is retained unchanged as upstream provenance, not the active manifest.

UniFFI 0.32.0 enables Askama configuration parsing. The released compatible Askama versions still use
`basic-toml`, which RustSec marks unmaintained under RUSTSEC-2026-0374. The root dependency policy
continues to deny the advisory: no ignore, source allowance or runtime dependency is added.

The patch changes only the active manifest's optional parser dependency and feature reference,
and the single `RawConfig::from_toml_str` parser call. It uses maintained `toml` with only parse,
serde and std features, already resolved by the independently locked shared-core workspace.
Template parsing, code generation, UniFFI versions, public schemas and cryptography are unchanged.
Malformed configuration diagnostics can contain the maintained parser's own wording.

Verification must run the upstream configuration/unit tests, actual UniFFI generation for Swift
and Kotlin with byte-for-byte baseline comparison, the unchanged dependency-policy check, shared
core/CLI consumer regressions, Clippy, and the runtime/tooling MSRV gates. Generated sources are never
edited by hand. A cache hit or source inspection is not binding-generation evidence.

Remove this patch and directory when a released compatible Askama/UniFFI dependency removes
`basic-toml`; regenerate the lockfile and repeat the binding comparison and policy gates.
Do not update vendored files without recording and reviewing the upstream source/diff again.
