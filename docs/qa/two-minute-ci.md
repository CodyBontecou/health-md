# Two-minute regression strategy

The complete retained regression suite is four parallel lanes. Every PR runs every
lane, including contract consumers. There is no change planner, broad nightly suite,
second browser matrix, duplicate platform test matrix, or release-only revival of
retired regression coverage.

| Lane | Retained boundary evidence | Warm local measurement |
| --- | --- | --- |
| Rust | Shared contracts/registry, independent core and CLI workspaces with all features, CLI/MCP behavior, CI deadline and native-scope failure checks | 11.6 seconds |
| Apple | Swift protocol/FFI packages, eight macOS SDK-to-real-file, native/Rust differential, durability/cancellation/profile/protection regressions, plus iOS compilation | 46.6 seconds in the concurrent run |
| Android | One Play E2E JVM configuration, settings/protection/date-window/planner checks, Rust↔Kotlin socket negotiation, real JNI fixtures, SDK fixture through Compose export and real SAF files, durable settings reopen | 26.3 seconds in the concurrent run |
| Web | Practice security/provenance/runtime checks and three Chromium journeys, notification-only Wake checks, complete static website/docs build/link validation, pinned Obsidian parser/fixture consumer | 34.3 seconds alone; 50.4 seconds concurrently |

The complete concurrent suite passed in **50.7 seconds** before the final commit.

These are development-machine measurements with dependencies and compilation outputs
available. They are not a hosted-CI SLA or clean-cache result. Native cold builds can
exceed 120 seconds before tests begin. The CI gate counts infrastructure time and
fails over budget. Until a real hosted run passes, the two-minute hosted objective
remains unverified. A runner-capacity or cache miss is not allowed to silently skip
coverage or widen the budget.

## Commands and prerequisites

`make test` runs the four scripts in `scripts/ci/` concurrently. The local command
requires an arm64 Mac with Xcode and iOS simulator, Rust 1.88, Java 21, pinned Android
SDK/NDK and cargo-ndk, a booted isolated Android device, Node and component dependencies.
Linux CI executes the non-Apple lanes on separate hosted runners. Dependencies remain
component-scoped; there is no root package manager or shared Cargo workspace.

Set `ANDROID_SERIAL` to the dedicated test target and `HEALTHMD_CI_ANDROID_ABI` to
`arm64-v8a` locally (`x86_64` in hosted CI). The Apple lane builds for a generic iOS simulator destination without booting a simulator. The Android
native UI test refuses the normal application ID and uses private synthetic storage.
Do not run instrumentation concurrently with Argent/UIAutomator on the same target.

Install each npm lockfile separately in `apps/practice`, `apps/wake`, `apps/website`
and `apps/website/docs-src`; install Practice's Chromium with Playwright. Check out
the external repository/revision in `apps/website/external-sources.json` into ignored
`.external/health-md-visualizations`, then install that checkout's lockfile. CI performs
these steps within its measured wall clock. The consumer check rejects a different
revision or tracked modifications. Website fixture checks fail if the consumer is absent.

`make test-*` and old test source files remain available for targeted diagnosis.
Their previous CI coverage is retired; none is implicitly required by this strategy.
Release packaging, signatures, artifact provenance and store publication are separate
operations and do not count as PR regression tests.

## What protects the budget

The wrapper starts a new receipt before work, kills the process group on timeout or
cancellation, and never accepts an old success. Xcode and Android inventories require
selected native test methods exactly once, with no skips or failures. JVM test results
are always regenerated even when compilation is cached. Test reports are cleared
before native execution. Caches accelerate compilation; they cannot supply a passed
regression result.

CI's final gate includes initial queue time, checkout, installations, cache transfer,
all four lanes, artifact/reporting and post-actions. A separate 90-second lane limit
reserves orchestration headroom. Initial hosted cold-cache and warm-cache runs must
both be observed; a timeout is evidence to reduce work or improve infrastructure,
not a reason to increase the stated two-minute target.

## Deliberately reduced coverage

Only Chromium remains in the Practice browser qualification; it makes no Firefox,
WebKit, latest-two-browser, assistive-technology or production-readiness claim. Mobile
UI covers one representative Android export path using synthetic SDK responses;
Apple covers SDK capture through real file I/O and builds the iOS app. iOS simulator
UI automation is retired because intermittent runner startup hangs exceeded the budget;
it does not prove real HealthKit/Health Connect authorization, purchase/store services,
all accessibility settings, OS versions, background execution, reconnect UI, Wear or
F-Droid behavior. Rust retains broad inexpensive contract coverage on one OS/toolchain;
PRs no longer repeat Windows/macOS/Linux or MSRV matrices. Release artifact checks
still validate the artifacts being published.

Historical export/protocol fixtures and public schemas are unchanged. Changing a
contract still requires updating every producer/consumer coherently. Add new regression
evidence at the cheapest boundary that would have caught a real bug, preferably inside
an existing test, and measure the complete lane again.

## Rollout

Merge the workflow and scripts together. Switch external branch protection from the
seven retired component contexts to `CI / CI` once available. No branch-protection
setting, runner provisioning, remote branch, release, or deployment is changed by this
local implementation. Inspect real hosted queue/setup/test/post-action timings before
claiming the two-minute objective has been achieved.
