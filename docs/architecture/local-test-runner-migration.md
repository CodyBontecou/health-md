# Local test runner migration

Date: 2026-10-07. Status: Apple pilot implemented; broader cutover proposed.

Health.md can move more test execution onto its own machines, but replacing GitHub Actions requires preserving orchestration, trustworthy merge evidence, platform coverage, and release qualification. The recommended first migration is to make complete component verification runnable locally, move selected CI jobs to dedicated runners, and retain Actions release and qualification paths until their trust dependencies have an explicit replacement.

## Choose the migration boundary

| Option | What changes | Main consequence |
| --- | --- | --- |
| Manual local verification | Developers run component checks before pushing or merging. | Lowest infrastructure effort; automatic enforcement disappears unless a trusted service reports results. |
| Actions with self-hosted runners | Existing workflows call local verification commands on owned machines. | Moves compute while retaining GitHub triggers, checks, logs, and workflow artifacts. |
| External CI with local workers | An independent coordinator receives events, schedules machines, and reports results to GitHub. | Removes Actions orchestration; the team owns its replacement. |

A self-hosted runner remains part of GitHub Actions, with machine and toolchain maintenance owned by the team. This distinction matters if the goal is reducing hosted minutes versus removing the platform dependency. [GitHub self-hosted runners](https://docs.github.com/en/actions/concepts/runners/self-hosted-runners)

## Current coverage and local gaps

The repository contains 27 workflow YAML files, including eight component CI workflows, Apple nightly tests, and release, review, audit, and evidence workflows. Some Wear release workflows are dormant. Seven stable final contexts are documented for branch protection; the TypeScript core context remains a candidate. These documented contexts do not establish the repository's live protection configuration. [Workflow inventory](../../.github/workflows/README.md)

`make test` already routes production checks by component, while `make test-portable` separately checks the TypeScript candidates with exact Node 24.21.0/npm 11.19.0. Neither command constitutes full replacement coverage for the workflows. The portable migration must preserve current native/Rust gates until its separate promotion requirements pass. [Root router](../../Makefile), [candidate policy](../../.github/workflows/README.md#portable-typescript-candidate)

| Component | Coverage to preserve beyond the root test command |
| --- | --- |
| Apple | iOS/macOS units, UI and iPad tests, coverage, warning checks, generated documentation, and localization validation. |
| Android | Flavor-specific tests, lint/builds, native instrumentation and direct E2E, Wear emulator smoke, and Rust/Kotlin interoperability. |
| Rust core and CLI | macOS/Linux/Windows execution, MSRV, formatting/linting, generated bindings, dependency policy, packaged crates, and CLI/MCP smoke tests. |
| Practice | Full `check:ci` browser/security/audit gate, native feature policy, and synthetic PDF qualification. |
| Wake | Locked installation, tests, type checking, and Wrangler dry-run packaging. |
| Website | Generated-reference drift, localization/docs builds, external Obsidian consumer validation, and scheduled/dispatched checks. |

Sources: [Apple CI](../../.github/workflows/apple-ci.yml), [Android CI](../../.github/workflows/android-ci.yml), [Rust core CI](../../.github/workflows/core-rust-ci.yml), [CLI CI](../../.github/workflows/cli-ci.yml), [Practice CI](../../.github/workflows/practice-ci.yml), [Wake CI](../../.github/workflows/wake-ci.yml), [Website CI](../../.github/workflows/website-ci.yml).

Practice also verifies the literal workflow command `run: npm run check:ci`, and its synthetic provenance boundary includes the workflow file. Extracting commands requires a deliberate update to this qualification contract, rather than deleting the workflow or weakening the checks. [Qualification verifier](../../apps/practice/scripts/verify-qualification.mjs), [boundary manifest](../../apps/practice/scripts/synthetic-boundary-manifest.mjs)

## Proposed execution architecture

Keep native component scripts and independently scoped lockfiles/build outputs. Add a lightweight root router for selecting components and execution modes; a repository-wide build framework is unnecessary. An illustrative interface, which does not exist yet, is:

```sh
make verify COMPONENT=apple
scripts/verify --sha <commit> --base <base-commit> --profile pr
```

Provide quick developer checks and complete merge/release checks explicitly. Resolve immutable source and base SHAs, run in a fresh checkout, record runtime/toolchain versions, and retain logs, test results, artifact hashes, and the selected coverage profile. Identify the verification scripts, lane manifest, change detector, and component locks so changed gate definitions cannot reuse older results. Record PR head, tested merge, and base SHAs separately; invalidate merge evidence when its base or tested merge changes. A local JSON receipt supports traceability; acceptance as merge evidence requires an authenticated trusted reporter and verifiable association with the tested source.

Keep GitHub App credentials in a trusted supervisor outside checkout/test processes. It should validate receipts and report success only after every required OS lane succeeds. Missing workers, cancelled jobs, malformed evidence, and unresolved routing must never become a green gate; uncertain routing can conservatively select full coverage.

Preserve the current changed-path policy: contract/shared-core changes fan out to all affected consumers; detection failures must fail the gate; full scheduled/manual/release qualification must run even when PR paths would skip a component. The existing composite action obtains PR paths through the API and intentionally fails closed. [Change detector](../../.github/actions/component-changes/action.yml), [repository policy](../../AGENTS.md)

Use dedicated Mac capacity for Apple, Linux capacity with emulator acceleration for Android, and Windows execution for Rust/CLI coverage. Apple nightly already uses self-hosted runners, providing a starting point. [Apple nightly](../../.github/workflows/apple-nightly.yml)

Owned runners need availability monitoring, scheduling, concurrency limits, cancellation, timeouts, and retained diagnostics. Use clean isolated environments for PR execution and keep release identities outside that pool: GitHub explicitly documents persistent-runner and fork-PR compromise risks. Ephemeral registration alone does not wipe the machine; cleanup remains an operator responsibility. [Runner security](https://docs.github.com/en/actions/reference/security/secure-use#hardening-for-self-hosted-runners), [runner lifecycle](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)

## Preserve GitHub merge enforcement

External tests can publish commit statuses through GitHub's API; a GitHub App can provide richer checks. Required checks can accept a specific App identity, so transition both the context and accepted source deliberately. A check named like the old Actions job does not automatically satisfy an Actions-bound requirement. [Commit statuses](https://docs.github.com/en/rest/commits/statuses), [Checks integration](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-checks), [protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

Publish results for the exact commit GitHub evaluates. Required checks must pass on the latest SHA; when the test merge commit has status, GitHub evaluates that commit. A merge queue creates another SHA, requiring external CI to handle `gh-readonly-queue/{base_branch}` branches. Always produce a conclusive aggregate result, including valid unaffected-component decisions, rather than leaving required contexts pending. [Required-check behavior](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks), [merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)

## Keep release qualification intact initially

Moving PR compute does not make CI workflow files disposable. CLI release qualification requires successful exact-SHA Actions runs for CLI, Rust core, Apple, and Android. Android releases reuse Android CI against an exact SHA, and recovery validates retained run/attempt/job evidence. Retain main-push/manual/reusable qualification routes initially. [CLI qualifier](../../apps/cli/scripts/qualify-exact-ci.py), [CLI release](../../.github/workflows/cli-release.yml), [Android release](../../.github/workflows/android-release.yml)

Other dependencies need separate migrations:

- Android Play mutations are restricted to protected Actions workflows using GitHub OIDC and Google Workload Identity. [Play ownership](../../apps/android/PLAY_STORE_COMMANDS.md)
- CLI signature verification names the GitHub workflow OIDC issuer/identity; crates publishing requires a retained successful CLI release run and trusted publishing. [Signer ledger](../../apps/cli/release-identities.json), [release verifier](../../apps/cli/scripts/verify-release.py), [crates publisher](../../.github/workflows/cli-publish-crates.yml)
- Apple coordinates draft releases, App Store Connect submission/review approval, release publication, and announcements. [Apple release contract](../../.github/workflows/README.md#apple-release-trigger)

Leaving Actions entirely requires replacement identity federation, provenance, protected approval boundaries, and accepted qualification evidence. GitHub OIDC and its normal build-attestation flow are workflow based. Logs/build artifacts also need independent storage and retention; GitHub release assets can still be uploaded through the REST API. [OIDC](https://docs.github.com/en/actions/concepts/security/openid-connect), [attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations), [workflow artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data), [release assets](https://docs.github.com/en/rest/releases/assets#upload-a-release-asset)

## Staged cutover

1. Inventory live required checks and all workflow/release consumers; agree whether the target is owned compute or removal of Actions.
2. Extract complete verification commands without changing coverage, component boundaries, or Effect promotion status.
3. Run equivalent local and hosted jobs against identical SHAs; investigate differences and prove clean-run reproducibility across the existing OS matrix. Exercise failures, cancellation, unavailable workers, changed bases, and affected/unaffected path decisions before trusting the replacement gate.
4. Move execution component by component. For external CI, validate the reporter first, then switch required contexts and their trusted provider atomically; preserve rollback.
5. Keep exact-SHA release qualification and publishing on Actions until replacement identity and evidence policies are implemented and validated.
6. Remove obsolete workflows only after every trigger, gate, artifact consumer, and release dependency has a working successor.

## Implemented Apple pilot

[PR 197](https://github.com/CodyBontecou/health-md/pull/197) introduces one optional unsigned iOS
unit-test lane with an isolated checkout, fresh simulator and scoped diagnostics. The runner belongs
only to the new private [health-md-local-ci controller](https://github.com/CodyBontecou/health-md-local-ci).
The public repository runs hosted tooling safety tests; its reviewed controller workflow template
is under `scripts/local-actions/`. Private dispatch resolves and validates exact public-main source
before scheduling the Mac. Labels provide routing, not access control: private repository registration
prevents public PRs from targeting this everyday Mac. Runner hooks are not used as an admission boundary.

The pilot was merged normally after all four required contexts passed. The
[first GitHub-to-Mac run](https://github.com/CodyBontecou/health-md-local-ci/actions/runs/37671168284)
passed 2,344 iOS tests, with 13 skips and no failures, at merged source
`e8f93620db153751f827ab754e3c8fa2105ea555`. The Mac job took 7m21s; downloaded xcresult and
receipt agree, and its simulator was removed without errors. Earlier local verification passed
2,330 tests before the main-branch refresh. Seventeen safety tests cover
source/result validation, private registration, archive validation, cancellation and scoped cleanup.
The first suite reproduced a known main capability-test omission. The Apple/Android expectation
correction and Android SDK setup correction subsequently landed on main; after refreshing, the pilot
diff contains only runner tooling and operating documentation. It changes no public contracts or release workflows. Evidence is retained in ignored `.pi/local-actions-pilot`.

Live main protection was inspected on 2026-10-07: four contexts are currently required—Apple CI,
Android CI, CLI CI and Website CI—and each accepts the GitHub Actions app. This differs from the seven
contexts documented on the active candidate branch; no protection settings were changed. Controller
checks appear in the private repository and do not satisfy public merge or release qualification.

This pilot establishes owned Mac execution for trusted merged source. It does not yet migrate the
complete Apple matrix, Android/Linux/Windows capacity, public PR checks or release publishing.
