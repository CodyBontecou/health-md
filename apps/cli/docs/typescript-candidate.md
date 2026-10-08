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

## Exact codec successor authority

`core-ts-exact-codecs-v1.json` records the reviewed producer's complete 56 inputs
and 34 core module outputs. The 43-input/26-module eligibility cohort described
above remains immutable historical authority: all 41 other input bytes and all
26 module bytes are retained. The successor adds twelve Number/Value/Canonical
JSON/facade source, test and vector inputs and eight module outputs, with the
reviewed package/README replacements and one additional Catalog literal vector.
The private literal `@healthmd/core-ts/candidate/codecs` exposes the four original
codec functions and their selected types; no reader, AST, token type, wildcard,
extra dependency or separate Effect installation is admitted.

Five tracked implementation receipts must remain raw-byte identical, passed,
and accepted at their exact task/source/patch/review fingerprints. Catalog uses
a separate closed `CatalogLiteralDataAuthority`: its 96-scene vector and current
partial receipt are tracked, while its exact original Stage1 approval and
original partial receipt are embedded as canonical base64 in the cohort.
The guard verifies the blob schema, canonical encoding, original byte lengths
and SHA256 before strict UTF-8/JSON parsing and exact semantic chain checks.
Historical scratch paths and producer-host compiler locations are audit
provenance only; consumer checks never require or open those paths. Catalog's
partial literal approval gives no implementation, behavior, runtime, module,
grant, public or consumer authority. Its source and test remain absent.

The guard's 203 frozen filesystem failures retain all 84 historical cases and
add 119 exact input/output/receipt/cohort/Catalog mutations. Each new mutation
starts from an authenticated disposable baseline and calls the actual same
validator used for ordinary inputs. Embedded evidence supplies owned local
copies for the Catalog approval/archive tests; altered hashes are never adopted.
Only the owned temporary tree is removed. Source, installed packages, accepted
cohorts and receipts are never mutated by the negative drivers.

Qualification requires the coordinator's sequential exclusive core check,
pinned offline `npm ci --offline --install-links --engine-strict --no-audit
--no-fund` in this CLI component, then its full `npm run check`. Actual check and
integration status is recorded in the task receipt and execution plan; the
producer's 1253 portable tests/19 guards alone do not install this consumer.
The separately frozen CLI result envelope remains uncompiled prospective work
until its own checks and review; this cohort does not admit its public grammar
or rendering. Native bundles, source reads, health grants, exports, full public
profiles and Rust retirement retain their separate owners and qualification.
Rollback restores the predecessor guard/cohort and packed CLI together.
