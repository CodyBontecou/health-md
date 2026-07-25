# Claude Code Implementation Prompt (Testing Epics + Parallel Lanes)

Paste the prompt below into a fresh Claude Code session.

```text
You are working in `/Users/codybontecou/projects/health-md/app`.

Primary goal: implement all open testing epics/todos already created in the todo system, using strict TDD (RED/GREEN/REFACTOR) for every testing-related task.

## Non-negotiable process
1) Follow `docs/testing/TDD.md`.
2) Use `docs/testing/TDD-COMPLETION-TEMPLATE.md` when updating todo evidence.
3) Do NOT close a testing todo without explicit RED/GREEN/REFACTOR evidence appended to that todo.
4) Claim todos before working on them.
5) Keep commits small and scoped to one todo (or one tightly coupled pair).

## Open epics
- TODO-e55ebc57 (critical manager tests)
- TODO-3c87c09b (HealthKitManager coverage)
- TODO-18623788 (export contract/golden tests)
- TODO-122b6cb8 (UI/E2E tests)
- TODO-ed4e3730 (CI quality gates)
- TODO-2b0cd43e (lifecycle/concurrency stress)

## Where to find todos (important)
Use either method:
1) **Todo tool/API**: run `todo.list-all`, then `todo.get <ID>`, `todo.claim <ID>`, `todo.append <ID>`, `todo.update <ID>`.
2) **File fallback** (if todo tool is unavailable): todos are markdown files in `.pi/todos/`.
   - ID mapping: `TODO-<hex>` -> `.pi/todos/<hex>.md`
   - Example: `TODO-e55ebc57` -> `.pi/todos/e55ebc57.md`
   - Full index: `docs/testing/TODO-INDEX.md`

## Parallelization strategy
Create a dependency-aware execution plan first, then implement in parallel lanes.

### Wave 0 (foundations; parallelizable)
- Lane A: TODO-8c1f46d5 (shared runtime service test seams)
- Lane B: TODO-4a1235b3 (HealthKit query facade)
- Lane C: TODO-b17073fc (add UI test target/scheme)
- Lane D: TODO-6ec96488 (coverage collection in CI)
- Lane E: TODO-e4c602d1 (lifecycle workaround audit)

### Wave 1 (depends on wave 0 outputs)
- Lane A (E1 managers): TODO-8bc77fb6, TODO-d37d504d, TODO-8077baec, TODO-de41226b, TODO-52990079
- Lane B (E2 healthkit tests): TODO-5fa156af, TODO-e0f18bb4, TODO-4fac60b8, TODO-847ca530, TODO-c389cf56
- Lane C (E4 UI infra): TODO-7d7b3e68, TODO-e21370a4
- Lane D (E3 export contracts): TODO-030548a9, TODO-ea804396, TODO-bc0165f1, TODO-62b7743d, TODO-8b99740d, TODO-f4593f18
- Lane E (E6 lifecycle): TODO-1ff7bb36, TODO-1eac8522, TODO-32c61b8b, TODO-5d392723
- Lane F (E5 CI gates): TODO-55c3e0ec, TODO-eb0b1b50, TODO-a55c5428, TODO-74fdb59f, TODO-188d2f69, TODO-9f8571ce

### Wave 2 (hardening + final pass)
- Full test suite pass on iOS + macOS.
- UI tests pass in CI workflow.
- CI gates enforced (coverage + warning + todo TDD evidence guard).
- Close remaining todos with complete TDD evidence blocks.

## Required first actions
1) `todo.list-all` and verify all IDs above are present/open.
2) Produce a concise dependency graph and execution plan with parallel lanes.
3) Start Wave 0 immediately by claiming one todo, implementing via TDD, and appending evidence.

## Implementation quality bar
- Prefer protocol seams/adapters over brittle monkey-patching.
- Keep tests deterministic (fixed dates/timezones, fakes for OS/network/StoreKit/HealthKit).
- For UI tests, use accessibility identifiers (not display text selectors).
- For exporter contracts, use fixture/golden comparisons with actionable diffs.
- For lifecycle tests, use bounded stress loops and deterministic timeouts.

## Reporting format after each completed todo
- Todo ID
- Files changed
- RED command + failure summary
- GREEN command + pass summary
- REFACTOR changes + verification commands
- Any follow-up todo created/updated

Begin now.
```
