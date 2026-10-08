# Health.md shared Rust core

This independent workspace owns deterministic post-capture semantics, profile rendering and artifact planning, the canonical metric/profile registry, its thin UniFFI boundary, and the transport-independent direct protocol. HealthKit, Health Connect, native UI/localization, runtime capability checks, permissions, storage, lifecycle, networking, and export side effects remain native.

The tooling toolchain is pinned in `rust-toolchain.toml`. Runtime crates retain a separately tested Rust 1.85 MSRV; `xtask` and the UniFFI 0.32.0 binding generator require the pinned Rust 1.88 toolchain.

## Checks

```sh
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check -p healthmd-core -p healthmd-protocol -p healthmd-core-uniffi --all-features --locked
python3 scripts/import-native-registry.py --check
python3 scripts/generate-registry-adapters.py --check
python3 scripts/generate-sleep-profile-registry.py --check
python3 ../contracts/validate.py
```

## Metric registry

`crates/healthmd-core/registry/metric-registry-v1.json` is the canonical, canonical-JSON inventory for:

- `apple_health_data_v8`
- `android_frozen_v4`
- `android_analytical_v5`

It owns stable semantic and persisted native identities, order, source units/aggregation metadata, aliases, output keys, profile availability, and explicit platform non-equivalences. It does not own SDK type objects or runtime availability decisions.

`import-native-registry.py` checks the immutable pre-cutover Apple/Android snapshots plus the reviewed semantic crosswalk and is retained as independent migration evidence. `generate-registry-adapters.py` projects the authoritative JSON into thin Swift/Kotlin catalog constants and generated website/reference data. Generated regions are committed and checked for drift; edit the registry, not generated rows.

`metric-registry-v2.json` is a separate, successor-only inventory for `apple_health_data_v11` and `android_sleep_v6`, derived by `generate-sleep-profile-registry.py`, which also generates Android's and Apple's separate successor registry-hash constants. It does not replace v1, change its hash, or change the native catalogs' legacy default. Android Light and Apple Core have distinct semantic identities in this inventory; v6 never emits the historical Core alias. Explicit successor sessions use independent semantic input/canonical model v2 and render input/artifact plan v2 alongside registry v2; historical defaults, schemas and exact fixtures remain v1. Daily successor rendering and `sleep::read_public_sleep_context` are shared-core compatibility foundations, not evidence of qualified native capture, writers or readers. See [the qualification contract](../contracts/sleep-attribution/v1/contract.md).

## Semantic input and reduction

`crates/healthmd-core/src/semantic.rs` implements the internal `healthmd.semantic_input` v1 contract under `packages/contracts/semantic-input/v1/`. It accepts bounded coarse batches from already-captured native models, validates exact timestamp/binary64/unit envelopes, filters persisted selection IDs, retains opaque platform extension tokens, applies deterministic daily reducers/shared BMI derivation, and produces typed Apple period roll-ups. It does not query either health SDK or render public bytes.

The UniFFI boundary exposes one ephemeral `CoreSemanticSession` object with `process_batch` and idempotent `cancel`; cancellation is checked between bounded record groups. `CORE_API_VERSION` is 4, while immutable semantic-result v1 bytes continue to declare their original API value 3. Historical semantic input, canonical result, registry, and persisted-state defaults remain independently pinned at 1. Explicit sleep successors select input/model/registry v2 and carry atomic frozen capture authority; result v2 declares core API 4. The synthetic differential fixture is shared by Rust, Swift, and Kotlin and contains no production health data.

## Rendering and artifact plans

`crates/healthmd-core/src/render/` implements `healthmd.render_input` v1 and artifact-plan v1 with separate Apple-v8, Android-frozen-v4, and Android-analytical-v5 profile modules. A bounded `CoreRenderSession` consumes one completed semantic result plus explicit, output-key-attested presentation facts from the same frozen native capture. It renders frontmatter/Bases, Markdown, CSV, ordered JSON, Apple roll-ups, individual/Daily Note plans, profile-exact merge behavior, and owner-date/byte-scoped API envelopes; paths, collision keys, write modes, byte counts, and SHA-256 values are returned without touching a destination.

`CoreLosslessArtifactStream` incrementally frames raw bytes, JSON-array items, or RFC 4180 rows while retaining only sequence/digest state. Planned streams finalize with the same content-free identity/path/media/write/count/checksum evidence as inline artifacts. Native code writes returned chunks into existing atomic spools and still owns ZIP, SAF/security-scoped URLs, HTTP, and credentials. Independently frozen Swift/Kotlin renderer goldens, full Android request replay, and the exact Rust differential plan live under `packages/contracts/render-input/v1/`. Production authority remains legacy until M6. The explicit sleep successors render daily/API formats through independent render-input/artifact-plan v2 without widening v1. Kotlin-generated successor handoffs and a core-generated v6 plan under `packages/contracts/render-input/v2/fixtures/` exercise real post-capture sessions and native plan verification without invoking Health Connect or a destination. They are not independent native public-writer goldens or JNI/device qualification. Successor managed Markdown merge requires complete matching profile/clock/attribution authority and metadata surfaces, preserving user YAML blocks and prose while refusing implicit historical migrations. Prepared canonical native API JSON is supported only with explicit UTC/metric authority, owner-date and projected-value attestation; local-calendar or imperial documents are rejected, not relabeled. API unit tables come from pinned profile metadata with semantic-unit equivalence checks, never presentation-only labels. Native capture, local API normalization, successor calendar/range output, merge/Daily Note adoption and native/consumer qualification remain incomplete.

## Direct protocol foundation

`crates/healthmd-protocol` remains the Rust authority consumed directly by the CLI. Its pure
`foundation` module now also backs a coarse synchronous UniFFI surface at independently versioned
protocol API revision 1. Native packages can retrieve deployed constants; fingerprint exact
canonical Apple-v1 and Android-v2 requests; canonicalize complete control messages; encode/decode
opaque 512 KiB `HMDDIRCT` chunks; and reuse deployed transfer negotiation. A narrow JSON-free
crypto conformance surface verifies reviewed new-pairing client transcripts and derives the
existing session key from fixed 32-byte inputs. Selected Rust-owned vectors are zeroized, but
UniFFI-generated transport buffers are not guaranteed to be wiped, so production key custody stays
native pending a dedicated secret-FFI review.

The foundation preserves Apple/Android legacy pairing selectors 1/2 and now also advertises and
verifies shared high-entropy selector 3. Apple application version 1, Android application version 2,
shared secure/binary framing version 1, and existing discriminator/associated-value bytes remain
unchanged; selector 3 has its own canonical cross-language fixture. Native networking, trust,
credentials, persistence,
lifecycle, sockets, and health exporters remain untouched. Stateful secure-channel sequence,
replay rejection, nonce/key lifecycle, seal/open, reconnect/trusted transcripts, and session
persistence remain security-review gated and are not exported by UniFFI.

## Binding generation

The scripts build the host `cdylib` and generate deterministic source with the pinned UniFFI generator:

```sh
./scripts/generate-swift-bindings.sh
./scripts/generate-kotlin-bindings.sh
# or
cargo run --locked -p xtask -- bindings swift
cargo run --locked -p xtask -- bindings kotlin
```

Generated Swift/Kotlin bindings are committed in their native packages. Compiled Apple/Android libraries remain ignored source-built artifacts.
