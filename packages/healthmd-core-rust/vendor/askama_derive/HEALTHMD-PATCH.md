# Askama build parser patch

Upstream: askama_derive 0.16.0, https://crates.io/crates/askama_derive/0.16.0
Published crate SHA-256: `e1c7065972a130eafa84215f21352ae15b4a7393da48c1f5e103904490736738`. Upstream license notices and sources are retained.

UniFFI 0.32.0 enables Askama's configuration parser. Published Askama 0.16.1 and UniFFI 0.32.2 still depend on archived basic-toml, which fails RUSTSEC-2026-0374. This patch substitutes maintained toml 1.1.3 (already locked by UniFFI) only for build-time Askama configuration parsing. UniFFI, template parsing/generation, native ABI and export/protocol sources remain unchanged.

Changes from the published source: Cargo.toml replaces the optional basic-toml dependency/config feature with toml; src/config.rs calls toml::from_str. No other upstream source is changed. Cargo.toml.orig, the packaged Cargo.lock and .cargo_vcs_info.json retain original provenance. HEALTHMD-PROVENANCE.json records every published archive file hash; the two intentional modifications differ from those upstream hashes. Cargo cache metadata is not part of the published archive.

Remove this path patch when the pinned upstream UniFFI/Askama dependency chain no longer enables basic-toml. Do not add an advisory ignore or relax dependency policy. Qualify the dependency gate, upstream parser tests, shared-core tests/MSRV and byte-identical Swift/Kotlin binding generation after changes.
