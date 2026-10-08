# Fast TypeScript development

This isolated tool adds blocking Effect diagnostics and dependency-based test selection
for the portable core and CLI candidates. It does not modify their locked build tools,
qualification scripts or frozen source cohorts. Development results are
not qualification receipts. Each component still owns its dependencies and output cache.

Use Node **24.21.0** and npm **11.19.0**. Install this tool once with
`npm --prefix scripts/typescript-dev ci --ignore-scripts --no-audit --no-fund`.
Then run `npm --prefix scripts/typescript-dev run setup` to retain only the selected
diagnostic compiler from the platform distribution. Repeat setup after reinstalling.
The target component must also have its existing locked dependencies installed.

From the repository root:

```sh
# TypeScript + Effect diagnostics, no runtime tests (checks source and tests).
node scripts/typescript-dev/dev.mjs check core
node scripts/typescript-dev/dev.mjs check cli

# Static checks followed by tests affected by staged, unstaged and untracked changes.
node scripts/typescript-dev/dev.mjs affected core
node scripts/typescript-dev/dev.mjs affected cli --base origin/main

# Static checks followed by one or more exact test entries.
node scripts/typescript-dev/dev.mjs selected core tests/source-catalog.test.ts
node scripts/typescript-dev/dev.mjs selected cli tests/surfaces/result-envelope.test.ts

# Verify runner selection and real Effect compiler diagnostics.
npm --prefix scripts/typescript-dev run test:runner
```

The static lane enables TypeScript's existing strict settings plus `noImplicitReturns`,
`noFallthroughCasesInSwitch` and `noUncheckedSideEffectImports`. Twelve Effect correctness
rules fail the command, including discarded Effects, missing `yield*`, missing services
or errors, unsafe channel assertions, nested Effects, unawaited Promises and duplicate
Effect installations. Style suggestions are disabled. The patched Go compiler is invoked
directly; third-party installation scripts and compiler patching are unnecessary.

Affected selection builds a fresh esbuild dependency graph from current test entries.
It follows transitive imports, includes test helpers, handles new/deleted files
conservatively, and selects all CLI tests for core changes because the core is an external
packed dependency. Component metadata changes select the full component suite.
Shared contract and development-runner changes also select full component coverage. Git
detection failures and incomplete graphs fail instead of returning success. A zero-test
result still runs static checks. Explicit selection rejects nonexistent test paths.

Selected tests are freshly bundled into the component's existing `dist/tests` layout and
executed as JavaScript using `node:test`. This preserves fixture-relative paths and package
export checks. The runner refreshes only selected test bundles; it never deletes other
outputs or rewrites the full build's metafile. The full qualification command must rebuild
after source changes. Static caches live in each component's ignored
`node_modules/.cache/healthmd-dev`; no shared build daemon or global cache is needed.
Existing CLI packed-core qualification remains a prerequisite
for authoritative consumer results; this development lane does not admit a new core cohort.

During implementation, use static checks first and the affected or selected test lane
for behavioral feedback. Before accepting a component change, run its existing full
`npm run check` under the refactor's normal qualification procedure. Do not rerun a passing
full check unless relevant inputs changed or a failure or unresolved concern warrants it.

Prefer compile-time proof for service requirements, discriminated-union exhaustiveness
and invalid typed combinations. Use compile-only negative probes with `@ts-expect-error`
when a public type contract needs regression protection: the compiler must reject the
invalid usage and fail when that protection disappears. Retain behavioral tests for
untrusted input, serialization, cross-language compatibility, cancellation, scope lifetime,
resource cleanup and native integration. Do not delete fixture or behavioral coverage
merely because a value also has a TypeScript type. Audit redundant tests per module.

The pinned tool is `@effect/tsgo` **0.51.0**, whose published compatibility table includes
TypeScript **7.0.2**. Its wrapper is JavaScript and the selected compiler is Go. The
upstream platform package also bundles Rust Oxlint addons and extra compiler versions;
our explicit setup removes those unused artifact directories from this tool's installed
dependency. Diagnostics refuse an untrimmed distribution. This keeps Oxlint outside the
executed tool graph and reduces local disk usage. See
[Effect's devtools documentation](https://effect.website/docs/v4/getting-started/devtools)
and the [compiler compatibility table](https://github.com/Effect-TS/tsgo/blob/main/README.md#supported-package-versions).

Other hosts, editor integration and promotion into mandatory qualification/CI need
separate validation. Adding a `plugins` entry to an unpatched TypeScript compiler alone
does not establish build-time Effect diagnostics. This tool's regression probes exercise
the actual diagnostic compiler rather than relying on configuration presence.
