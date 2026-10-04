# Integration and conformance gates

## What this lane verifies

Python validates closed schemas, typed fixtures, cross-field/path/scope/revision/authority/cursor hazards,
canonical bytes and SHA-256 values, references, inventory hashes and preserved historical fixtures.
Refinement vectors include paired/native-delegation + host-store bootstrap, fresh in-bounds scope/root
changes, candidate-bound control plan/approval relay, exact projection profile/media/bytes and source-
specific identity/metadata/precision hazards. No caller UUID or rehashed JSON is a stored grant.
This is specification conformance only. No new Rust, Swift or Kotlin DTO generation/producer test has
run. Python HMAC vectors use a public synthetic key; no native credential/key access occurred.

Fixture generation is reproducible with Python standard library only:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 packages/contracts/agent-bridge/v1/build_schemas.py
PYTHONDONTWRITEBYTECODE=1 python3 packages/contracts/agent-bridge/v1/build_fixtures.py
python3 packages/contracts/validate.py
python3 -m unittest discover -s packages/contracts -p 'test_validate_agent_bridge.py'
```

Generators write only their new versioned schema/fixture paths. They never update manifest pins,
metric registry, historic fixtures, product source or todos. Ordinary validation/tests are read-only.
Do not use generator output as proof of native generation or replace expected fixtures merely to pass.

## Required exact native fixture-generation path (proposed, not executed)

1. **Rust protocol models, independent workspace:** add strict DTOs in
   `packages/healthmd-core-rust/crates/healthmd-protocol/src/v4.rs` and source-query/agent v1 types there.
   Preserve legacy `wire.rs` and v1/v2 decoding behavior; add extension negotiation as a separate route.
   Add `tests/agent_bridge_v4_vectors.rs` consuming canonical candidate JSON directly. After native
   byte agreement is reviewed, create its Cargo packaging mirror under
   `tests/fixtures/agent-bridge-v1.json` and add the mirror pin centrally. Proposed gate:
   `cargo test -p healthmd-protocol --test agent_bridge_v4_vectors --locked`, then the independent
   core workspace format/tests/clippy/MSRV and bindings gates. Do not call this a Rust query engine.
2. **Swift producer:** add `AgentBridgeV4VectorTests.swift` under
   `apps/apple/Packages/HealthMdConnectivity/Tests/HealthMdConnectionCoreTests/` with explicit v4 Codable
   DTOs/encoder, not synthesized associated-value wire cases. Encode every candidate positive payload,
   compare canonical bytes/hash to the same fixture, and write *candidates only* to a lane scratch path
   when `HEALTHMD_GENERATE_AGENT_BRIDGE_V4=1`. Generation command after that test exists:
   `HEALTHMD_GENERATE_AGENT_BRIDGE_V4=1 swift test --package-path Packages/HealthMdConnectivity --filter AgentBridgeV4VectorTests`
   from `apps/apple`. Confirm a reviewed Swift-generated export intent/plan/execute/receipt corpus and
   reject all negative decoding/semantic cases before setting provenance to native-generated. Include
   source-specific native identity, unsupported metadata omissions, exact HKObjectType identifiers and
   NSDate binary64-bit/checked normalized-time vectors; constructors may inspect SDK type constants,
   never read user health data as fixture generation.
3. **Kotlin producer:** add `AgentBridgeV4InteropTest.kt` under
   `apps/android/direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/`; implement explicit closed
   kotlinx.serialization DTOs/canonical encoder. Consume the same canonical fixture and all negative
   cases (no health-data reads); generate scratch candidates only when
   `HEALTHMD_GENERATE_AGENT_BRIDGE_V4=1`. Proposed command:
   `HEALTHMD_GENERATE_AGENT_BRIDGE_V4=1 ./gradlew :direct-protocol:test --tests com.healthmd.direct.protocol.AgentBridgeV4InteropTest`
   from `apps/android`. Then Kotlin fake Health Connect repository tests for every typed operation,
   provider/version/features/history and cancellation. No invented APIs or reusing Swift messages.
4. **Review closure:** compare Rust/Swift/Kotlin encoded bytes and digests, operation/result semantics,
   sanitized rejection codes, checked count/decimal/timezone/source-precision rules and cursor HMAC.
   Independently derive binary64 time views from raw returned Date bits with exact rational nearest/ties-even
   rounding, preserve actual Instant nanos/client versions, and reject invented cross-source metadata.
   Verify issuer-owned stored references/delegation bounds and both first/future scope/root journeys,
   every control candidate/approval binding and projection product/selector approvals, pre-read job journal,
   timestamped intraday observations, base-carriage/fingerprint correspondence and exact profile/media/bytes.
   Projection fixtures assert synthetic base DTO shapes, not native v2 decoder/frame conformance. The three native
   outputs must independently agree with each other *and* the reviewed candidates. Hash evidence names
   exact source commit/toolchain and commands. Update new manifest provenance only after review; never
   rewrite historical v1/v2/v3/pairing/setup/export fixtures or claim native pass from Python tests.

All listed native test files/commands are future targets, not files claimed present or commands run.
Coordinator can schedule lanes for these after integrating the contract foundation.

## Downstream requirements

| Lane | Foundation to consume | Required implementation evidence |
|---|---|---|
| B06 | source-query catalog/request/response, v4 independent negotiation | Native repositories/evaluator, all nine fixed operations, installed SDK/provider/history evidence, exact-unit/time identity, budgets/snapshot/cursor/cancel; one service operation, after-first-unlock behavior |
| B07 | same schemas + catalog source/peer binding | Source-aware client/operations/MCP/Apps/PNG and capability discovery; old Android/iPhone rejection, mixed device selection, bounded cycle-safe traversal; read-only stays read-only |
| B08 | Explicit projection intent product, planned selector catalog, native source observations, agent_projection_job/1 and exact v4 execute/manifest/commit fingerprint | Native trace: object/field/detail approval → pre-read journal → preserved capture → unchanged generic base file/frame transfer → exact resume/once-only append; no daily/raw product reinterpretation, point timestamp/identity loss or query-cache recapture |
| B09 | complete output settings/capture axes, explicit/saved/profile policies | Swift+Kotlin native resolver/production exporter journals; preferences unchanged on every outcome, no hidden archive, host-safe path/format write semantics |
| B10 | sanitized stored native/host references, bounded delegation derivation, zero-health plan/approval relay | Native/host private-store bootstrap and fresh scope/preapproved-root journeys; caller JSON never grants rights; fake backend proves **zero health reads/earliest-date calls/preview/quota/output/settings/credential/wake enrollment**; all_available unresolved, grant/revision/expiry/peer/destination tests |
| B11 | typed local recipe CRUD/revisions and separate run | Private atomic store/CAS, typed catalog, no stored authority/health/paths on phone; fresh approved plan and exact resume |
| B12 | bounded stored inspection scope, typed native-profile candidate plans/approval/bound receipts | Separate exact native configuration decision/grant, Configuration Protection/entitlement, zero-health planning, atomic rollback/CAS/idempotent replay, last-profile/import-rebind blocks; activation cannot retarget frozen jobs |
| B13 | host schedule and independent mutation/run authority | Deterministic DST/catch-up/run identity, unknown-job reconciliation, credential/session limits on each desktop OS; no unattended phone promise |
| B14 | typed destination/schedule candidate proposals, plan/approval relay and pending-binding digest | Exact target/value/profile/credential-reference revision approval, native rebind/protection, zero-health plans, exact cadence, pending recovery retains original authority; B16 gate before widening API recovery |
| B17 | explicit packaging and immutable inner/container manifest | Bounded native streaming ZIP, inner exact bytes/digests/path limits, interrupted staging/commit/cancel cleanup; no frozen settings/snapshot additions |
| B18 | independent profile dictionary + source mapping review | Profile/schema-correct artifacts with no values/permission claims; alias/unit/signature/manifest and consumer tests |

Feature negotiation advertises installed support only after those gates. Planned inventory targets
are not a boolean that implementers may flip based on a green schema test.

## Consumer and release gates

- Preserve every Apple v8, Android frozen v4/analytical v5, raw-snapshot, v1/v2/v3/pairing and frozen
  Shared Setup/semantic/render fixture. No schema-signature generation in this foundation.
- Independently validate Rust core/protocol and CLI workspaces/lockfiles; add fake-peer hello and
  extension/base version tests before 4 is advertised.
- Run Swift Connectivity and focused iPhone settings/query/export/authorization tests + iOS build;
  Kotlin direct-protocol and both Play/F-Droid focused native tests/builds; bindings/MSRV gates.
- CLI/MCP accepted and advertised schemas must agree, including offline catalog vs installed runtime.
  No shell/SQL/URL/file-read authority, remote mutation or hidden mobile-setting write.
- Website capability/support/docs review and external Obsidian parser tests if new projection/dictionary
  is consumed; shipped output byte compatibility remains mandatory. Reader implementation precedes
  writer default adoption. B19/B20 remain blocked on separate approval; no unified-v9 dependency here.
- Physical exact installed-build LAN/Tailscale and macOS ARM/Intel, Linux ARM/x64 (including headless
  Secret Service), Windows matrices: authority/revocation/history/locks/service lifecycle, budgets,
  resumable transfer/idempotent append/merge/path races and cancellation acknowledgements.
- Stable CLI 1.0 remains its existing frozen scope. New controls/Android typed queries require a separate
  scope/release decision and retained qualification; no availability or latest-release mutation here.

## Central registry regeneration dependency

Coordinator's baseline `make check-core-registry` reports pre-existing importer drift **only** in
`known_capability_ids` and `available_capability_ids_by_platform`; metric/profile rows are identical.
`registry-adapters --check` passed independently. This lane adds only planned product inventory rows;
it never edits metric registry or frozen setup/semantic fixtures. Coordinator must centrally regenerate
health-free capability indices after serial integration, review that no metric/profile data changed,
and rerun all registry/consumer gates. A local contract validation pass is not that regeneration gate.
