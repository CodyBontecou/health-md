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

Root `make test` and `make test-apple` include iOS simulator work. They are broad routes, not a default host-only loop. Use the owning component's explicit host commands, such as `make -C apps/apple test-macos`, when their scope is appropriate.

Simulator/emulator QA, device installation/launch, UI automation, and Argent require explicit authorization for the current task. A request to implement, polish UI, or run tests does not authorize those workflows. Mark relevant unrun native/visual surfaces as gaps rather than claiming another platform's tests verify them.
