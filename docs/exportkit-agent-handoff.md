# ExportKit / ExportAutomationKit Fresh-Agent Handoff

Last updated: 2026-06-04

## Completed todos

- `TODO-3d4a7bd6` — Define ExportKit / AutomationKit architecture and package boundaries.
- `TODO-0c2024a0` — ExportKit: generic format descriptors and renderer registry.
- `TODO-add4f202` — ExportKit: path templates, placeholder variables, and path safety.
- `TODO-b660fec5` — ExportKit: destination folder, bookmark access, and reusable file writer.
- `TODO-8671cf6d` — ExportKit: write modes and pluggable merge strategies.
- `TODO-6763a336` — ExportKit: orchestrator, progress, cancellation, and result/history model.
- `TODO-67d6341c` — ExportKit: planned-file preview builder.
- `TODO-0321050f` — ExportKit plugins: daily note injection and individual entry exports.
- `TODO-b800e4a5` — Port Health.md aggregate exports onto ExportKit adapters.
- `TODO-890757af` — ExportAutomationKit: schedule model, date math, and persisted automation config.
- `TODO-2361fb54` — ExportAutomationKit: server registration and scheduled APNs worker contract.
- `TODO-fc02b9c1` — ExportAutomationKit: silent push and BGTask background runner.
- `TODO-da038d39` — ExportAutomationKit: pending export store and fallback notifications.
- `TODO-647b36f0` — ExportAutomationKit: notification tap router and foreground retry coordinator.
- `TODO-1da5c192` — ExportAutomationKit: trigger-source abstraction.
- `TODO-d38b2d4d` — Port Health.md connected Mac export jobs to ExportKit snapshots.
- `TODO-971c5a71` — Build non-health sample adapter and parity regression test suite.
- `TODO-003a9ee3` — Document reusable ExportKit and ExportAutomationKit adoption guide.

## Todo completed in this session

### `TODO-003a9ee3` — adoption docs

Completed the reusable adoption documentation for apps that want to adopt `ExportKit` and `ExportAutomationKit` without Health.md-specific dependencies.

Acceptance criteria covered:

- New app checklist exists in `docs/exportkit-adoption-guide.md`.
- Minimal code examples cover records, format descriptors, renderers, portable profiles, path templates, planned files, destinations, file writers, write modes/merge strategies, orchestrator/progress/results, previews, plugins, portable snapshots, schedules/date math, remote schedule payloads, pending requests, background runner, tap retry, and trigger policies.
- Examples are based on the non-health invoice sample from `HealthMdTests/Export/NonHealthExportKitSampleTests.swift`.
- Health.md adapter examples are separated in their own section and call out the app-owned files that bridge Health.md settings/renderers/plugins/scheduling/sync to generic APIs.
- The guide includes a background export failure/tap-to-retry lifecycle diagram.
- Docs index and architecture document now link to the adoption guide.

## Next recommended todo

None. `TODO-003a9ee3` was the last todo in the established work order, and no fresh agent is needed for this work-order chain unless new todos are created.

## Architecture decisions

Primary architecture note: `docs/exportkit-automationkit-architecture.md`.

Decisions added/confirmed in this session:

- Added `docs/exportkit-adoption-guide.md` as the app-facing companion to the architecture document.
- Kept adoption documentation generic and invoice-sample based rather than Health.md-domain based.
- Documented the current local-source staging under `HealthMd/Shared/ExportKit/` and `HealthMd/Shared/ExportAutomationKit/`; package extraction/public access cleanup remains future work.
- Explicitly separated Health.md adapters from reusable APIs in the guide.
- Used a plain text lifecycle diagram so the docs do not depend on Mermaid or other Markdown extensions.
- Did not change production behavior.

Prior decisions still in force:

- `ExportKit` core must not depend on HealthKit, Health.md models, `HealthData`, `MetricSelectionState`, `HealthMetricsDictionary`, health metrics, Obsidian, or vault concepts.
- `ExportAutomationKit` depends on `ExportKit`, not Health.md.
- Generic code is staged locally under `HealthMd/Shared/ExportKit/` and `HealthMd/Shared/ExportAutomationKit/` until package extraction is worthwhile.
- `MarkdownMergeStrategy.defaultManagedSectionNames` is domain-free; apps supply managed section names explicitly.
- Health.md owns `MarkdownMerger` as a compatibility facade for Health.md-managed Markdown sections.
- Manual and scheduled Health.md exports preserve existing output semantics through `HealthAggregateExportAdapter`, `VaultManager`, and Health.md automation adapters.
- Scheduled exports remain behavior-compatible and write to the local iPhone destination.
- Server/APNs registration is routing-only and never sends HealthData, exported file contents, vault paths, filename templates, selected metrics, metric names, or metric values.
- Background failure persists pending export requests.
- Tapping fallback notifications retries the exact stored request in the foreground.
- Connected Mac remains a manual local-peer target; it is not a cloud/server transfer path.

## Files changed in this session

- `docs/exportkit-adoption-guide.md` — new reusable adoption guide with checklist, invoice examples, package/module boundaries, ExportKit/ExportAutomationKit setup flows, security/privacy guidance, and failure/tap-to-retry lifecycle diagram.
- `docs/index.md` — added adoption-guide link.
- `docs/exportkit-automationkit-architecture.md` — linked to the adoption guide near the top.
- `.pi/todos/003a9ee3.md` — claimed and closed the todo with completion notes.
- `docs/exportkit-agent-handoff.md` — updated for completion/no-next-todo state.

Working tree note: this checkout still contains many pre-existing/unrelated or previous-slice modifications/untracked files beyond this session, including Xcode project changes, earlier ExportKit/ExportAutomationKit sources/tests, Health.md export/automation files, and prior docs. Do not attribute all `git status` output to `TODO-003a9ee3`; inspect diffs before assigning ownership.

## Tests/checks run in this session

- Relative Markdown link check via `python3 -c '...'` for `docs/index.md`, `docs/exportkit-adoption-guide.md`, and `docs/exportkit-automationkit-architecture.md` — passed.
- `git diff --check` — passed.

No app tests were run because this slice changed docs only. Previous handoffs documented unrelated full-suite failures in pricing/runbook tests (`PricingAnalyticsClientTests.testQueueIsCappedAndDropsOldestPayloads()` timeout/restart and `PricingExperimentRunbookTests.test1499ExperimentRunbookCapturesControlGates()` expecting `Results status: pending`).

## Current risks/open questions

- Generic ExportKit/ExportAutomationKit code is still staged locally; package extraction remains future work.
- Some current local-staging `ExportAutomationKit` types still use internal access because they live inside the Health.md app target; package extraction should make public adoption APIs explicit.
- The scheduled APNs worker implementation is not present in this checkout; only app-side contract/docs exist in `worker/scheduled-apns-worker-contract.md`.
- Portable profile stores enabled plugin IDs generically, but app-specific plugin configuration remains in app-owned snapshots by design.
- Full macOS/iOS suites were not rerun for this docs-only slice.

## Important invariants for every future todo

- Manual Health.md exports remain behavior-compatible.
- Multi-format export preserves current filename and collision behavior.
- Folder/subfolder/filename templates preserve existing behavior for safe paths; unsafe write paths must not escape the selected destination.
- Write modes overwrite/append/update preserve existing behavior.
- Markdown update mode preserves user sections/frontmatter.
- Export preview continues showing aggregate files, Daily Note Injection, individual entries, warnings, and truncation.
- Plugins/side effects run once per exported record/date, not once per selected aggregate format.
- Daily Note Injection paths remain vault-root-relative and must not be overwritten by aggregate exports.
- Scheduled background exports remain behavior-compatible and write to the local iPhone destination.
- Server-side APNs registration never sends HealthData, exported file contents, vault paths, filename templates, metric names, selected metrics, or metric values.
- Background failure persists pending export requests.
- Tapping fallback notifications retries the exact stored request in the foreground.
- Shortcut exports retain local iPhone destination semantics.
- Connected Mac exports keep output parity with local exports.
- Connected Mac remains local peer sync; do not turn it into a cloud/server transfer abstraction.
- `ExportKit` core must not depend on HealthKit, HealthData, MetricSelectionState, HealthMetricsDictionary, health metrics, Obsidian, or vault concepts.
- `ExportAutomationKit` must not depend on Health.md and must depend on ExportKit only.

## Exact next steps

No next todo exists in the established work order. If new follow-up todos are created later, start a fresh context, read this handoff plus `docs/exportkit-automationkit-architecture.md` and `docs/exportkit-adoption-guide.md`, then claim exactly one new unblocked todo.

## Ready-to-copy fresh-session prompt

No prompt is needed because no work-order todo remains. Create a new prompt only if new todos are added.
