# Local development-lane verification

Verified on macOS arm64 using Node 24.21.0, npm 11.19.0, `@effect/tsgo` 0.51.0
and TypeScript 7.0.2 on October 8, 2026. Other hosts and editor integration are
not qualified by these runs.

- Locked offline installation with lifecycle scripts disabled passed. Explicit setup
  removed unused platform artifacts; installed tool size fell from 233.3 to 97.3 MiB.
- Nine runner regression tests passed. Actual compiler probes accepted valid Effect
  code and rejected a discarded Effect, missing `yield*` and a direct assertion that
  erased an Effect error channel. Selection tests cover transitive dependencies,
  helpers, missing entries, unknown/deleted files, metadata and shared-contract fan-out.
- Core source/test static checks passed. Initial observed run: 995 ms; latest warm
  affected run: 69 ms. These are local observations, not performance guarantees.
- Explicit catalog selection passed all 106 tests in 363 ms including warm static
  checking and bundling. A second layout-sensitive codec API entry passed all 81 tests.
- Changing the development runner selected all fifteen core entries. All 1,359 tests
  passed in 2,375 ms including static checks and bundling. This is development evidence,
  not a replacement full qualification receipt.
- All 53 outputs from the previously qualified core build retained their exact hashes
  after the selected/full development runs. Core source, compiler configs, package
  locks, qualification scripts and frozen cohorts were not changed by this work.

The CLI source check passed, but checking its test code failed at
`apps/cli/tests/surfaces/stdio-framing.test.ts:96`: the Effect supplied to `runPromise`
retains an `unknown` service requirement. TypeScript reports TS2379 and the Effect
compiler additionally reports `missingEffectContext`. The frozen, uncompiled MCP
candidate remains pending repair; this tool does not suppress or baseline that error.

During implementation, the first probe used a double assertion through `unknown`,
which this Effect rule did not reject. The verified probe uses a direct assertion;
arbitrary type assertions still require review. The first selected run also exposed
fixture-relative path assumptions; selected bundles now use the existing `dist/tests`
layout. Both issues were corrected before the passing results above.
