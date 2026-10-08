# Portable core candidate

This independently locked foundation is a development candidate. Existing Rust/native production code, launchers and contracts retain authority. The private candidate entrypoints are `@healthmd/core-ts`, `@healthmd/core-ts/host-interfaces`, and explicit `@healthmd/core-ts/candidate/{catalog,normalize,query,registry}` subpaths after a local build. These subpaths expose the existing qualified ESM modules and declarations without a wildcard or hidden-path import. No product imports or native linking are introduced.

Use Node **24.21.0** with bundled npm **11.19.0**. From this directory run `npm ci` and `npm run check`. The check verifies runtime/lock identity, typechecks ES-only portable source and Node test code separately, emits ESM/declarations, runs compiled JavaScript with `node:test`, and checks portable imports/globals plus Effect identity. `dist` and dependencies are ignored outputs. `npm run test` consumes the most recent build; `npm run check` always rebuilds first.

Effect is the only runtime dependency. TypeScript 7 and esbuild use pinned optional Go binaries during development. Tests use Node assertions and Effect Layers, without Vite/Vitest/Rollup or a TypeScript runtime loader. Portable TypeScript uses `.js` module specifiers for ordinary ESM emit. Dependency declarations are skipped during source checking because Effect references host type names; own portable source still has no Node/DOM ambient types. Installed native binaries and every supported host require separate qualification.

`CandidateSession` is an injected, scoped test seam: acquire a synthetic resource, inspect its health-free readiness and release it on success, typed failure or interruption. It implements no health query, export, protocol, destination or native capability. Tests use deterministic fake Layers, signal gates and a virtual clock rather than live data or wall-clock sleeps.

Boundary checks traverse every own source module (including unused ones) and the neutral esbuild graph. They reject unsupported imports, nonliteral dynamic imports and host global references, and verify a single Effect installation. These checks are a candidate admission guard, not a complete native VM/global audit. Native host, public profile, signed release and retirement evidence remain separate.

Packed hosts qualify the complete reviewed source/build input cohort and the sixteen accepted emitted files. CORE-CANDIDATE-API reviews only this export manifest and documentation metadata over the accepted REGISTRY-READER code authority; the historical registry receipt retains its original manifest hash. Future semantic source additions require separately reviewed cohort rebinding and affected host integration before CLI qualification. The registry reader still requires reviewed host byte binding; traversal fake byte attestations and transport completion do not prove native authorization, serialization, full query grammar or complete health coverage.

The private `@healthmd/core-ts/candidate/codecs` subpath reexports the original
`createExactJsonNumberParser`, `createExactJsonCodec`,
`createCanonicalJsonSerializer`, and `serializeExactJsonNumber` functions.
Its ten named types retain the original opaque handles and fixed failures.
Compose the value factory's original `codec` and opaque `readerToken` into the
serializer constructor; a token from another factory fails authentication.
The facade exposes no reader, AST, named token type, wildcard, or new algorithm.
It retains default serde numeric classes, strict UTF-8, decoded duplicate keys,
UTF-8 key order, compact bytes and the explicit compact-LF policy under the
original private budgets. Pure graph ownership grants no source, permission,
or operation lifetime authority. Root exports and the six earlier package
entries remain unchanged. A portable core check qualifies this facade's source
and declarations; packed CLI/MCP adoption still requires the separately reviewed
successor cohort and consumer binding. Catalog's 96-scene fixture remains
Stage1 data-only and supplies no implementation or capability authority.
