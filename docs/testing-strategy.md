# Test selection and build reuse

The root [verification policy](../AGENTS.md#verification-policy) governs local agent work. Product/public-contract and security regressions remain required; speed comes from selecting the right surface and reusing compatible builds, not weakening assertions.

## Choose a verification tier

| Tier | When | Surface |
|---|---|---|
| Focused feedback | Red/green iteration; edits affecting the tested behavior | Owning behavior test(s), relevant features, cheap type/lint checks |
| Affected regressions | Completion of a coherent change/batch | Owning module plus affected interfaces/consumers, once against the finished inputs |
| PR CI | Integration candidate | Fail-closed affected-job selection; all selected checks remain blocking |
| Extended qualification | Release, requested qualification, or changes to that surface | Full OS/flavor/device matrix, coverage, MSRV, bindings, packaging, provenance, release smoke |

Public schema/wire, crypto/authority, persistence/recovery, FFI/binding, platform-specific, and uncertain-impact changes escalate to every affected producer/consumer check. Follow the root contract workflow. Skipping an opt-in local workflow is a reported gap, not proof that another platform covers it. Preconfigured CI/release workflows retain their own qualification surface.

Keep a verification receipt in the task/PR: command, relevant source/dependency/fixture inputs, toolchain, features/configuration, result, and unrun surfaces. Reuse a pass only while those inputs match. After a relevant edit, rebuild/retest; after an unrelated baseline failure, isolate its smallest failing command and report the blocker rather than repeating all suites.

## Agent plan, guard, and receipt workflow

1. **Load instructions.** Start Pi at the worktree root with trusted project resources, then check `/verification-status`. For component-directory sessions use `bash /path/to/health-md/scripts/agent-pi.sh` so the guard is explicitly loaded. Existing sessions need `/reload`; project trust and disabled extensions can prevent automatic discovery. Other harnesses must load root/nearest `AGENTS.md` and use the portable runner below; their hooks are not installed automatically.
2. **Plan before checks.** In Pi call `verification_plan` with the task, input files/directories, `focused`, `affected`, or `qualification` tier, relevant toolchains and configuration. Its result loads root/owner instructions and this guide. Include sources, dependencies/lockfiles, fixtures, generators, feature/configuration inputs, and every affected consumer. Declare risk drivers (`public-contract`, `security`, `persistence`, `ffi`, `platform`, `uncertain`) and the escalation rationale. A new plan revokes pending approvals. Read owner instructions before editing too; a plan does not excuse earlier instruction loading.
3. **Run or reuse.** Use `verification_run` with a command and worktree-relative `cwd`. Known direct shell checks require a plan and get observed receipts, but only runner-owned exit-code/toolchain-checked passes are eligible for reuse. Set `reuse: true` after checking scope completeness; default execution never silently skips a check. Unchanged reruns warn unless `rerunReason` explains the repetition. Broad qualification warns when the plan has no `reason`, rather than blocking legitimate contract/security escalation.
4. **Finish with evidence.** Call `verification_report` with relevant `notRun` entries (`surface`, `reason`), then summarize commands/results, original execution versus reuse, and gaps in the task/PR. Pi also writes a report on agent completion, including pending blocked opt-in requests. `/verification-status` shows its path. Reports distinguish observed tool completion from runner passes and mark source-stale checks; they do not certify release qualification.

Known simulator/emulator/device/native-UI commands and every Argent tool are blocked without a human-only approval. A blocked call displays `/verification-allow <request-id>`; the user reviews the task and exact tool arguments in a confirmation dialog. Approval covers one identical request, expires after ten minutes, and is never saved in receipts, restored on reload, or inferred from prompts/environment variables. Plan/session/branch changes revoke it; unused approvals expire at agent completion. Prefer approving an explicit recorded-flow runner for a multi-step authorized QA flow, rather than a blanket device permission. Non-interactive runs without a confirmation UI remain blocked. Otherwise record the workflow as not run.

Receipts live under ignored `.pi/verification/<session-id>/`. They fingerprint selected tracked/untracked input bytes (including additions/deletions), instruction files, selected toolchain executable paths/version probes (Node and the runner's Bash are always included), inherited environment (digest only), loaded runner/policy identity, command, configuration, and tier. A pass can replay only when these match and inputs remain unchanged across execution; a later failure prevents replay of an earlier pass. Choose all relevant toolchains, for example `rust` **and** `cargo`, or `node` and `python`; selection remains the agent's responsibility. Inputs are paths, not globs. Include ignored fixtures/generated dependencies explicitly when relevant. Installed dependencies must match the declared lockfiles; a receipt cannot establish that by itself. Keep secrets/health data out of commands and plan descriptions; command output is returned, not stored in receipt JSON.

The guard is a conservative workflow check, **not a shell/OS security sandbox**. It covers known command routes, common shell wrappers/substitutions, and Pi tool calls (including nested calls routed through Pi). Arbitrary code, unknown/renamed scripts, direct processes started by other extensions, and human `!` shell commands are not comprehensively mediated. Review unfamiliar runners; the repository policy still applies. Disabling project resources disables automatic enforcement, and no receipt proves that the declared scope contains every required consumer.

### Other agent harnesses

Run the same workflow from the worktree root (Node 24+, Git, POSIX shell), choosing a unique session ID per agent. `PI_SESSION_ID` is the default when present:

```bash
node scripts/verification.mjs plan --session my-task \
  --task 'Fix verification command routing' --tier focused \
  --input scripts --input Makefile --input .github/workflows/testing-tools-ci.yml \
  --toolchain node --toolchain python --configuration 'Host-only default features'
node scripts/verification.mjs run --session my-task \
  --command 'node --test scripts/tests/verification-*.test.mjs'
node scripts/verification.mjs report --session my-task \
  --not-run '[{"surface":"Native/device QA","reason":"No product changes; not requested"}]'
```

Use `run --reuse` for an explicitly reviewed replay and `--rerun-reason` for intentional repetition. `check --command '<command>' --session <id>` exposes the same JSON decision for a harness pre-tool hook: exit 2 means block, and `warnings` should be surfaced to the agent. Check errors must block, not fall through to execution. The portable CLI has no opt-in bypass; an authorized device workflow needs a reviewed human-confirming harness adapter (Pi's is included). Guard installation must be confirmed in each actual harness; instructions alone do not install hooks.

## Development commands

Run commands from their owning component. Replace placeholders with the actual owner and test name; a filter is not permission to omit affected contract consumers.

| Owner | Focused feedback |
|---|---|
| Rust core or CLI | `cargo test -p <crate> <filter> --locked` with relevant features; `cargo clippy -p <crate> --all-targets --locked -- -D warnings` |
| Apple connectivity | `swift test --package-path Packages/HealthMdConnectivity --filter <Test>` |
| Apple app (macOS behavior) | `make test-macos TEST_FILTER=HealthMdTests/<Class>[/<Method>]` |
| Android app | `./gradlew :app:testPlayDebugUnitTest --tests '<qualified.TestClass>' --max-workers=2` |
| Android protocol | `./gradlew :direct-protocol:test --tests '<qualified.TestClass>'` |
| Practice | `npm test -- <test-file>`; `npm run typecheck` |
| Website | `node --test test/<file>.test.mjs` |

Prefer existing standalone packages/modules when they own the behavior. App-hosted XCTest and Android app JVM tests may still compile substantial native dependencies even when execution is filtered. Do not invent a separate test-only implementation to bypass that cost.

At the repository root:

- `make` shows the router's help without running tests.
- `make test COMPONENT=cli` (or another listed owner) runs only that component's regression route. Android's local route compiles one bounded Play Debug app variant plus its shared/Wear modules; use `make test-android-all` for all JVM variants or select F-Droid explicitly when that channel is affected.
- `make test-all` preserves the broad smoke sweep. It is expensive and does not replace complete component/release qualification.
- `make test-testing-tools` runs host-side orchestration regressions without product builds or devices. Install its small Python dependency with `python3 -m pip install -r scripts/testing-requirements.txt` in your tooling environment when missing.

Apple `make` shows developer commands without building; `make test` means macOS tests. `make test-ios` and `make test-platforms` explicitly select simulator work and require the current task's simulator authorization. No local simulator/emulator/device/Argent workflow is authorized merely by a request to implement or run tests.

## Build reuse and CI

- **Apple:** macOS tests and four documentation generators use `apps/apple/build/DerivedData/macOS`, isolated per worktree. Override `DERIVED_DATA_PATH` for concurrent independent jobs; use `MACOS_DEST` for an explicit architecture. Normal `xcodebuild test` checks/rebuilds current inputs. CI sets `MACOS_CODE_COVERAGE=YES` so docs reuse the coverage compilation profile; local feedback defaults to no coverage. Staging, schema-fixture protections, exact generated-artifact drift checks, and link validation remain enabled.
- **Nightly Apple:** one coverage-enabled macOS execution supplies both regression and coverage evidence, including the warning log.
- **Android PRs:** unrelated CLI changes keep live Rust/Kotlin interop without a full native build/device matrix. `healthmd-client`, CLI manifests/lock/toolchain, Android, shared-core, contract, and Android-workflow changes keep the full native matrix. Push/dispatched/release qualification remains full. Selected jobs must succeed; unselected jobs must explicitly be skipped, and invalid detector outputs fail.
- **Website:** CI installs locked dependencies once, then uses `npm run build:ci`, which builds/checks documentation once and retains localization, reference/agent-asset, visualization, and final-site checks. `npm run build` remains self-contained by installing docs dependencies first.
- **Practice:** retain independent browser servers, scanner/canary, qualification provenance, smoke, dry-run, and security gates. Its fast local bundle build does not justify adding a general-purpose cache or weakening provenance.

Caches are not qualification receipts. Keep source/toolchain/profile validation and exact-SHA release gates. Do not share mutable native build directories across concurrent worktrees or move blocking safety coverage to an unreliable scheduled runner.
