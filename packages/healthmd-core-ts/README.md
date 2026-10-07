# Portable core candidate

This independently locked foundation is a development candidate. Existing Rust/native production code, launchers and contracts retain authority. The public candidate entrypoints are `@healthmd/core-ts` and `@healthmd/core-ts/host-interfaces` after a local build. No product imports or native linking are introduced.

Use Node **24.21.0** with bundled npm **11.19.0**. From this directory run `npm ci` and `npm run check`. The check verifies runtime/lock identity, typechecks ES-only portable source and Node test code separately, emits ESM/declarations, runs compiled JavaScript with `node:test`, and checks portable imports/globals plus Effect identity. `dist` and dependencies are ignored outputs. `npm run test` consumes the most recent build; `npm run check` always rebuilds first.

Effect is the only runtime dependency. TypeScript 7 and esbuild use pinned optional Go binaries during development. Tests use Node assertions and Effect Layers, without Vite/Vitest/Rollup or a TypeScript runtime loader. Portable TypeScript uses `.js` module specifiers for ordinary ESM emit. Dependency declarations are skipped during source checking because Effect references host type names; own portable source still has no Node/DOM ambient types. Installed native binaries and every supported host require separate qualification.

`CandidateSession` is an injected, scoped test seam: acquire a synthetic resource, inspect its health-free readiness and release it on success, typed failure or interruption. It implements no health query, export, protocol, destination or native capability. Tests use deterministic fake Layers, signal gates and a virtual clock rather than live data or wall-clock sleeps.

Boundary checks traverse every own source module (including unused ones) and the neutral esbuild graph. They reject unsupported imports, nonliteral dynamic imports and host global references, and verify a single Effect installation. These checks are a candidate admission guard, not a complete native VM/global audit. Native host, public profile, signed release and retirement evidence remain separate.
