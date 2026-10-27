# Two-minute regression strategy

The retained suite runs on **one Linux runner**, with six concurrent groups. All
six run on every PR and main/testing push. Node, Python and pinned Rust are the only
host toolchains. No simulator, emulator, native SDK, browser installation or full
website/docs build is required. `make test` executes the same suite locally.

| Group | Regression boundary |
| --- | --- |
| Contracts | Manifest/schema/fixture/mirror validation, native metric registry and generator drift, CLI/MCP shared assets, CI deadline/result failure detection and local native coordinator queue/receipt behavior |
| Core | Real pure-Rust export/semantic/rollup behavior and protocol/crypto vectors, including versioned Apple and Android profiles |
| CLI | Transport-neutral operation validation, normalization, scope and backend contracts in `healthmd-operations` |
| Practice | Locked dependencies, type checking, all unit/API authorization and privacy regressions, production asset build, synthetic scanner/canary and security inventory |
| Wake | All authentication/replay/delivery policy tests and type checks for the notification-only Worker |
| Consumer | Pinned Obsidian parser/visualization tests, CSV combiner behavior, exact producer/consumer fixture equality and Apple/Android sample preservation |

These checks run against current source every time. Compilation outputs may be
cached; test results may not. The independent Cargo workspaces keep separate target
directories. npm lockfiles, builds and application boundaries remain component-owned.
The external consumer revision comes from `apps/website/external-sources.json`; a
different revision or tracked modification fails the consumer check.

## Timing and checkout

The workflow uses a shallow, blob-filtered Git checkout that omits media, archives,
fonts and spreadsheet binaries. All retained source and textual fixture inputs remain
present. Contract validation still checks the complete manifest, schemas, fixtures,
profiles and packaging mirrors; only documentation-link existence checking is omitted
because source-only checkouts deliberately omit linked media.

Each group has a 90-second process deadline. The aggregate command has a 110-second
limit. Dependency installation is inside the groups. Source checkout, toolchain setup,
cache restoration/saving and final reporting count against the 120-second workflow
limit, measured from creation (including queue time). The final gate rejects absent,
stale, dirty-source, skipped, failed or over-budget group receipts.

There is no extra gate job, runner handoff or artifact transfer between groups.
Cargo caches are restored/saved explicitly before the final timing check. There are
no checkout or cache post-actions after that check. GitHub's own job finalization is
verified using the completed hosted-run timestamps before claiming the target.

## Coverage deliberately retired

Native Swift/Kotlin compilation, FFI/JNI runtime checks, UI navigation, device storage,
HealthKit/Health Connect permission dialogs, live Rust/Kotlin sockets, browser engines,
all-locale website generation and full documentation link builds are not PR regression
requirements. SDK adapters and platform UI therefore have less protection. Pure shared
semantics and canonical byte fixtures protect their common export/protocol contracts,
but do not prove native capture, platform API compatibility or physical-device behavior.

The CLI executable/MCP transport and OS-specific keychain/network implementations are
not built by this minimum suite; the operations crate and shared public contracts are
covered. Practice retains production-disabled invariants and security behavior, but
makes no browser, assistive-technology, clinical, BAA, backend or production-readiness
claim. No health data is introduced into Wake.

Explicit diagnostic commands and historical test sources remain available. None is
moved to a mandatory nightly or revived as a hidden release regression matrix.
Store signing, packaging, artifact provenance and publication remain separate release
operations. The component reusable workflow interfaces invoke this same portable gate.

## Local execution and rollout

Install Node 24, Rust 1.88 and Python, then check out the repository/revision named by
`apps/website/external-sources.json` into ignored `.external/health-md-visualizations`.
`make test` performs the component npm installs and executes all six groups. No mobile
QA opt-in is needed for this portable suite. Logs and fresh timing receipts are written
to a unique ignored `.pi/ci/local-*` directory.

Require `CI / CI` in branch protection, replacing the seven retired component contexts
in a coordinated rollout. Branch protection and other branches' active jobs are not
changed automatically by this patch. Queue delays count as failures; a fast script
alone is not evidence that the complete CI met two minutes.

The four-runner predecessor passed locally in 43.1/34.6 seconds but failed in hosted
CI: Apple exhausted 90 seconds on cold native compilation, Web took 85 seconds before
setup/reporting, and runner queues alone exceeded the target. The single-runner replacement passed a cold-cache hosted run in **114 seconds**
including 18 seconds queued and 96 seconds assigned-runner time. All six current-source
groups passed; cache saving and final reporting were included. See PR #259 and run
40584677019 for the hosted evidence. Further final-revision runs verify repeatability.
