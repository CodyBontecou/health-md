# Test selection

The root [verification policy](../AGENTS.md#verification-policy) governs local work. Select checks from the owning source, tests, component Makefile, and configuration rather than treating a broad suite as the default feedback loop.

## Choose the surface

- During iteration, run the smallest owning behavior test and relevant cheap syntax/type/lint checks.
- At completion, run the affected module and interface regressions against the finished inputs.
- Public schemas, wire formats, crypto/authority, persistence/recovery, FFI, platform-specific behavior, and uncertain impact require every affected producer/consumer check. Follow the root contract workflow.
- Full OS/flavor matrices, coverage, MSRV, bindings, packaging, and release smoke are qualification surfaces. Run them when requested or when their surface changes; a focused pass is not release qualification.

## Focused feedback

Run commands from the owning component. Substitute the real test name and relevant features; a filter does not permit omitting affected contract consumers.

| Owner | Focused command |
|---|---|
| Rust core or CLI | `cargo test -p <crate> <filter> --locked` |
| Apple connectivity | `swift test --package-path Packages/HealthMdConnectivity --filter <Test>` |
| Android app | `./gradlew :app:testPlayDebugUnitTest --tests '<qualified.TestClass>' --max-workers=2` |
| Android protocol | `./gradlew :direct-protocol:test --tests '<qualified.TestClass>'` |
| Markdown inventory | `python3 -m unittest discover -s scripts/tests -p 'test_audit_markdown.py'` from the repository root |

For an owning macOS XCTest, prepare the shared core with `make prepare-healthmd-core-rust` in `apps/apple`, then select the class or method directly:

```bash
xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS \
  -destination "platform=macOS,arch=$(uname -m)" \
  -only-testing:HealthMdTests/<Class>[/<Method>] \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

Use the component's scripts and package configuration for Node.js tests and type checks. Prefer an existing standalone module when it owns the behavior; do not create a duplicate test-only implementation to avoid an app build.

## Reuse and receipts

Record the command, relevant source/dependency/fixture inputs, toolchain, features/configuration, result, and relevant unrun surfaces. Reuse a passing receipt only while those inputs match. Rebuild and retest after a relevant edit. Isolate an unrelated baseline failure with its smallest failing command instead of repeating whole suites.

Caches are not qualification receipts. Keep build directories isolated between worktrees and concurrent jobs; a normal incremental build still needs to validate changed inputs.

## Opt-in workflows

Root `make test` runs the [portable CI regression suite](qa/two-minute-ci.md) without native SDKs or devices. `make test-apple` is a broad diagnostic that includes iOS simulator work and requires explicit opt-in. Use the owning component's explicit host commands, such as `make -C apps/apple test-macos`, when their scope is appropriate.

Simulator/emulator QA, device installation/launch, UI automation, and Argent require explicit authorization for the current task. A request to implement, polish UI, or run tests does not authorize those workflows. Mark relevant unrun native/visual surfaces as gaps rather than claiming another platform's tests verify them.

## Native integration

Use three checkpoints. During edits, run focused owning tests and cheap checks. At
handoff, run affected-module regressions once. Before merge, the integration owner
compiles affected native apps against the combined final source. Leaf agents can
handoff with native compilation explicitly pending for that integration build;
pending work is not a passing native check.
GitHub runs the complete portable regression suite on pushes; an agent need not
repeat that whole suite after each edit. Recheck after integrating other changes
when they affect the verified inputs. Native compilation detects compiler/linker
and packaging integration failures; it does not prove startup or UI behavior.

```bash
make plan-native
make verify-native
# Narrow a known platform or select a different integration base:
make verify-native NATIVE_ARGS="--platform apple"
make verify-native NATIVE_ARGS="--platform android"
make verify-native NATIVE_ARGS="--platform all"
make plan-native NATIVE_ARGS="--base origin/main"
```

Automatic selection compares the merge-base with `origin/main` to the current
worktree, including staged, unstaged, deleted and nonignored new files. Apple or
Android paths select that platform. Shared packages, scripts, root configuration
and unknown ownership select both conservatively. Documentation-only changes and
known CLI/web/Practice/Wake-only paths select neither. Inspect the plan; override
selection for dependencies the path rules cannot identify. A missing base fails
rather than skipping compilation. CLI executable changes still need their owning
Cargo build/tests even though they select no mobile build.

The coordinator waits on an OS file lock in the repository's common Git directory,
so linked worktrees serialize their native builds. Start one invocation for a
finished batch of changes and allow it to finish before editing those inputs.
After acquiring the lock it recomputes selection and source identity. Waiting
and each build step default to 30 minutes; `--wait-seconds` and `--step-timeout`
set bounds. Cancellation/timeout terminates the owned build process group before
releasing the lock. This coordinates cooperating invocations; direct Xcode/Gradle
commands and separate clones do not participate. Use this entry point for heavy
agent builds rather than launching competing native sweeps.

On an arm64 Mac, Apple verification prepares source-matched Rust bindings/artifacts
with the existing reduced `ci-arm64` scope, then compiles unsigned Debug iOS
(simulator SDK, generic destination) and macOS apps. It never boots a simulator.
Android compiles the Play Debug APK with one arm64 ABI, two Gradle workers and
a single-use Gradle process (`--no-daemon`) so cancellation owns the build lifetime.
Both use installed SDK/toolchains; commands may download normal locked build
dependencies. F-Droid, Wear, release architectures, signing and store packaging
remain explicit checks when those surfaces change. Shared Rust/FFI changes select
both platforms and still require affected boundary/consumer tests.

Incremental outputs stay component-scoped and separate per worktree: Apple uses
`apps/apple/build/native-verification`, shared Cargo uses
`packages/healthmd-core-rust/target/native-verification`, and Android uses its
normal component build directories. Retain these while actively iterating to keep
builds warm; task-owned output cleanup still applies when retiring a worktree.
The coordinator always invokes the build tools; it never substitutes a stored
passing result for compilation.

Each invocation writes logs and an atomic `receipt.json` under ignored
`.pi/native-verification/<run>/`. Receipts identify the commit, a content digest
covering tracked and nonignored new files (including dirty/deleted source),
worktree, command, environment selectors, toolchain logs, timing and result.
A source change during execution makes the invocation fail. A dirty-source pass
applies to that exact snapshot; after committing or integrating, rerun against
the intended final commit. Receipts are local handoff evidence, not GitHub checks
or release qualification. They contain local paths/build logs and stay ignored.

For a bug fix, add the smallest reliable regression at the owning layer. Prioritize
startup failures, lost data, broken export/protocol bytes, unauthorized access and
recovery. If changed lifecycle, permissions, navigation or native runtime behavior
needs device verification, report the remaining gap and obtain the existing
explicit QA opt-in. Compilation and portable tests cannot certify those behaviors.
