# Opt-in TypeScript host candidate

This private development seam calls the shared portable `inspectCandidate` operation through `CandidateSession`. Thin CLI and MCP candidate functions share its acquisition, inspection and scoped cleanup. Their development envelopes are synthetic; current Rust commands, MCP tools, public launchers, installers, credential principals and releases remain authoritative.

Use exactly Node 24.21.0 and npm 11.19.0. Start with the committed portable core and its accepted build receipt. If its ignored build is absent, run its documented component checks first, sequentially with other core builds:

```sh
cd packages/healthmd-core-ts
npm ci --engine-strict --no-audit --no-fund
npm run check
cd ../../apps/cli
npm ci --install-links --engine-strict --no-audit --no-fund
npm run check
npm run candidate:smoke
```

`--install-links` is mandatory: npm packs the local core's declared `dist/core` files into this component's installation. A sibling symlink can resolve Effect through the sibling's `node_modules`, yielding a different singleton. Default install behavior is therefore not a supported bootstrap. The check fails on a symlinked core, stale/missing qualified core build bytes, edited or added unbuilt core source/config/test inputs, changed package identity, unreviewed dependencies, duplicate Effect or differing physical resolution. A changed common core requires new qualified build evidence and scoped adapter integration, rather than bypassing these checks.

The scoped lock records Effect 4.0.1, TypeScript 7.0.2, esbuild 0.28.2, Node types 24.19.1 and undici types 7.24.6. Build uses the selected Go compiler/bundler tooling; tests execute recursively discovered emitted ESM JavaScript with Node's test runner. Effect and the core remain external imports, so neither is bundled into test copies. The test seam verifies namespace and service constructor identity, lifecycle, failures, concurrent ownership and interruption with asynchronous cleanup acknowledgment, including interrupted cleanup defects. The host reconstructs interrupt-only causes with their cancellation IDs, stripping provider reasons and original annotations; synthetic provider errors do not escape through mixed causes. The prior integration hard-pinned the independently reviewed `core-ts-personal-v1.json` cohort SHA-256, its complete 34 input paths and 20 output paths, committed source revision `ba5c644ebca4c028fe8d60feb580a5e668965341`, and exact runtime. The complete maps retain the historical 28 inputs and sixteen outputs, with SERIALIZE-EXACT-NUMBERS' accepted three source/test/vector inputs and two unexported emitted files, followed by PERSONAL-CODECS' independently accepted three inputs and two unexported files. The prior exact-number 31-input/18-output cohort and its accepted refresh receipt remain immutable and separately pinned. Each accepted historical REGISTRY-READER, CORE-CANDIDATE-API, numeric-child, prior cohort refresh and personal codec receipt is checked for exact raw bytes, source, patch and independent review; the historical sixteen-artifact map and manifest remain separate authority. Input bytes, packed manifest equality and both source/packed output bytes are required. Runtime checks do not require Git or this cohort refresh's own receipt. Only exact core component-root `dist`, `node_modules` and `build` output directories are excluded. Any later core addition requires its own reviewed cohort delta. The retained twenty-four actual disposable-copy negatives cover source edits/additions/removal and symlinks, metadata/export edits, stale/missing/extra outputs and output symlinks, absent/tampered cohort and unreviewed numeric/personal delta evidence; personal source missing/edit/symlink and output stale/missing/extra/symlink cases extend the original sixteen cases. Copies are removed afterward.

The smoke command is explicitly fake-only. It prints ready outcomes for both candidate surfaces and two acquisitions/two releases. No listener, phone, health data, credential access, transport, filesystem discovery or retained user state is involved. Importing the host module does not execute the smoke.

Private `@healthmd/core-ts/candidate/{catalog,normalize,query,registry}` exports now expose the existing qualified modules and declarations. Packed CLI tests consume these entrypoints and verify the shared QuerySource constructor and physical Effect namespace; six hidden/internal paths remain unavailable. Future thin adapters must consume these common owners. This seam does not implement those operations, public CLI exit/framing behavior, MCP wire contracts, real host capabilities, signed Node distribution, legacy OS principal continuity, channel admission or Rust retirement. Remove these candidate files and ignored `apps/cli/dist`/`node_modules` to roll back; current product launchers and data remain unchanged.

CORE-CANDIDATE-API separately reviews the changed core package/README metadata pins. REGISTRY-READER retains its historical manifest hash and original code/build authority; the new metadata does not rewrite that receipt or alter the sixteen emitted files. The complete reviewed 40-input/24-output cohort retains the prior 34-input/20-output authority; packed manifest equality and source/build/filesystem guards remain mandatory. Future semantic source additions need a separately reviewed cohort rebind before CLI integration; new exports are not a bypass. Test traversal uses a trusted fake adapter with synthetic 64-byte accounting: transport completion with partial coverage is not complete health coverage, native authentication, complete grammar or exact serialization. Registry projection requires the host to bind reviewed canonical bytes before use.

The accepted `CORE-COHORT-PERSONAL-SLICES` integration extends the fixed candidate cohort to 40 inputs and 24 packed outputs using `core-ts-personal-slices-v1.json` (raw SHA256 `1dbee84851fb08b26a66d436014496f097fc94fafeeef880846897ca13ba4853`). All prior 34 inputs and 20 output bytes and their historical cohort/receipt authorities remain pinned. Exactly six source/test/vector inputs and four JS/declaration outputs add the independently accepted location-point projection and combined synthetic slice modules. The guard pins each accepted receipt's raw bytes, source, patch and review, preserves vector identities, and never reverse-pins its own integration receipt. These private modules remain absent from package exports and public launchers.

The check executes the frozen 63-case disposable filesystem catalog: the prior 24 cases, missing/edited/symlinked checks for each of six new inputs, missing/stale/symlinked checks for each of four outputs, an extra output, absent/tampered new cohort, and absent/tampered/unreviewed location and combined receipts. Prior personal cohort absence/tamper checks remain separate. Every clean copy must pass before mutation, expected failures must occur, and only the owned temporary tree is removed. Fixed source/output maps and the hard-pinned cohort precede any filesystem enumeration; discovered entries do not become authority.

Refresh requires the exact pinned core check, then offline CLI `npm ci --install-links --engine-strict --no-audit --no-fund`, then the CLI check, under an exclusive common-output window. Restore the prior committed guard/cohort and packed CLI together on rollback. Native frozen bundles retain separate qualification; this integration grants no native, durable authorization, source/profile, export/schema, user-data, or Rust retirement admission.

The accepted private iOS eligibility successor cohort is `core-ts-ios-eligibility-v1.json` (raw SHA256 `25b48beb5c7cd641d3161b3b362accdabf04bc0a5118042209651e88e18fe761`) at source `8a31e6f038d4f74b8ed6acb0da5003e0329714f5`. It fixes all 43 source/config/test inputs and 26 emitted module/declaration files, retaining every prior 40/24 byte and historical cohort/receipt. Exactly the independently accepted eligibility module, frozen 154-case vector and real Effect test add three inputs and two unexported outputs. Its raw receipt, original assigned source, repaired patch and independent review are checked before source/packed-byte qualification; this refresh's own receipt is never a reverse dependency.

The frozen 84 disposable filesystem negatives retain all 63 preceding cases and add 21: missing/edited/symlink for each of three inputs, missing/stale/symlink for each of two outputs, one extra output, absent/tampered successor cohort, and absent/tampered/unreviewed eligibility receipt. Each owned copy passes a clean baseline before mutation; only its temporary tree is removed. Complete fixed authority precedes filesystem discovery. Rebuild the core, refresh packed CLI offline with the pinned toolchain and existing cache, then run CLI/MCP checks sequentially under the exclusive core-output lease.

Eligibility remains a synthetic gate-only owned metadata handoff with zero personal observations and an original-Scope lifetime. Its accepted 154 frozen literals and six independent Scope reentry regressions prove this private boundary; they do not authenticate iOS eligibility, source/purpose/channel, durable grants, report/export, public profiles or OS budgets. The separately frozen discovery normalizer is not part of core authority. Existing public exports, launchers, Rust, native bundles and user state retain their separate qualification. Roll back the predecessor committed guard/cohort and packed CLI together.

## Historical Source Catalog authority

The immutable `core-ts-source-catalog-v1.json` cohort retains its exact 58
source/build inputs, 36 core module/declaration files and six strict tracked
implementation receipts. Its accepted integration remains historical private
portable evidence. The original codec cohort and Catalog literal-data
scope, bounded raw evidence, closed semantic chain and false admission flags
remain unchanged. Catalog's current passed implementation receipt is distinct
from its three historical partial/approval/archive embedded blobs. Historical
scratch paths remain inert provenance labels.

All 456 whole filesystem cases and original bindings are preserved: 203 run
against the historical codec 56/34 profile and 253 against the Source Catalog
58/36 profile. These profiles remain internal test stimuli. Both receive the
original `scripts/check-boundaries.mjs` bytes from the authenticated 8,065-byte
base64 literal (SHA-256 `3493efc…`) before pristine source validation. The
normal source now has the accepted repaired guard (`09076b02…`). Runtime
reconstruction uses the bounded literal, with closed fields, canonical base64,
exact length and SHA-256; it requires no Git executable, historical checkout,
or scratch-file read. All earlier 36 module bytes remain unchanged.

## Query and desktop usage successor

The mandatory consumer guard now binds the independently reviewed immutable
`core-ts-query-usage-v1.json` cohort, SHA-256
`a006edbe5577fc46cfb1057cf67591f6aed8b25d0c187b05ccfd950b3a711c45`,
1,651,134 bytes. It requires all 64 exact source/config/test inputs and all 40
exact emitted core modules/declarations, plus the complete 59-file producer
output set in the source component. Exactly six new source/test/vector inputs,
four emitted core files and the repaired boundary script extend the predecessor.
Manifest, exports and lockfiles remain unchanged. Typed-value and desktop
projection modules remain private and unexported.

The unchanged accepted full producer execution passed 1,544 emitted tests with
20 portable modules, one physical Effect installation and 19 boundary negatives.
Its complete source/output maps, 676 tool/runtime rows and three archive rows
are frozen producer evidence. Tool/runtime and scratch review references are
audit metadata; the guard does not turn them into new consumer dependencies.
Historical 1,359-test evidence cannot qualify the changed batch.

Normal admission requires the six historical strict implementation receipts,
final typed-value receipt `8e92cf…`, final desktop receipt `b9da69…`, and the
separately pinned accepted Source Catalog admission receipt. Raw lengths/hashes,
exact task/source/patch/review fingerprints, passed result, accepted review,
portable proof class and precise private targets are checked. The two new
producers retain their full limitations and remaining qualification arrays.
Root's final schema review records the current receipt pins; its earlier desktop
`62d5…` metadata pin remains historical. This task's receipt is never a reverse
pin or implementation authority.

The frozen corpus contains 617 negative scenes and 12 positive controls. The
first 456 negative objects and profile bindings remain unchanged. The 161 new
literal actions cover each new module/test/vector input, the changed boundary
script, new JS/declaration files, malformed/missing/tampered/extra/symlink paths,
strict producer and predecessor receipts, qualification omissions, cohort maps,
false admission flags and historical-boundary evidence. Pristine current and
historical source/module profiles, strict receipts/cohort and exact root output
directory exclusions supply the positive controls.

The guard copies owned disposable trees, validates each pristine scene, applies
its explicit filesystem or JSON action and calls the same validator used by
normal admission. Paths, groups and operations select only the mutation and
validator. IDs label observations afterward; expected outcomes are post-action
assertions. JSON changes never refresh expected hashes. Symlink targets retain
pristine data outside the copied tree; root, `dist`, `dist/core` and descendant
links are checked. Execution records contain complete ordered negative IDs,
profiles and actual fixed rejection codes, positive IDs and acknowledged cleanup.
They are emitted only after actual validation and temporary-tree removal.

This source update has not executed the 617 negatives, 12 positives, installation,
compiler, runtime or full CLI check. The installed CLI package still contains the
historical 36 files; 40 current source artifacts are pack-eligible emitted files.
Qualification requires independent source review and a separately reserved Root
window for the pinned Node 24.21.0/npm 11.19.0 command:

```sh
npm ci --offline --install-links --engine-strict --ignore-scripts --no-audit --no-fund
npm run check
```

The installation uses the approved offline cache, curated environment and empty
npm configurations. Current CLI/MCP sources retain their own qualification
requirements. Passing evidence may credit the unchanged complete core batch;
no additional producer run is needed unless relevant inputs change.

Finite native witness observations qualify only their recorded macOS/Swift/SDK
cases. They do not admit arbitrary Foundation values or native profiles. Actual
capture, browser/classification privacy, source/grant authentication, durable
storage or collectors, archive payload access, public contracts, unrestricted
full historical sessions, donor adoption and Rust retirement remain unqualified.
The 365-day mirror cannot reconstruct discarded short sessions, precollector
history or crash gaps; Windows/Linux and the required iOS exact-session S06
follow-up remain separate. Rollback restores a matching predecessor source,
packed output and guard through review; it cannot ignore extra current inputs
or silently adopt fresh hashes.
