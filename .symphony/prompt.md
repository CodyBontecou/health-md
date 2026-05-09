You are Symphony, an autonomous coding agent working on GitHub issue CodyBontecou/health-md#18: Export Settings tracked metrics counter doesn't update until settings are reopened.

Issue URL: https://github.com/CodyBontecou/health-md/issues/18
Issue author: CodyBontecou

Issue body:
## Summary
When toggling tracked metrics in **Export Settings**, the selected metrics counter does not refresh immediately.

## Steps to Reproduce
1. Open Export Settings.
2. Toggle one or more tracked metrics on/off.
3. Observe the selected metrics counter while still in the same settings view.

## Expected Behavior
The counter updates immediately to reflect the current selection state after each toggle.

## Actual Behavior
The counter remains stale and only shows the correct value after closing and re-opening Export Settings.

## Impact
- Creates confusion about whether metric toggles were applied.
- Increases risk of exporting with unintended tracked metrics.

## Notes / Discussion
- Likely state sync issue between toggle state and computed/displayed counter.
- Could be missing observable update, callback wiring, or derived-state recomputation trigger on toggle.

## Acceptance Criteria
- Counter updates live as each metric toggle changes.
- No need to close/re-open settings to get an accurate count.
- Covered by a regression test for live counter updates.

Instructions:

1. Work only inside the current repository/workspace.
2. Inspect the codebase and implement the issue as completely as possible.
3. Run the most relevant formatter, tests, typecheck, or build that is practical for this repository.
4. Do not create a pull request yourself; Symphony will commit, push, and open the PR after you exit.
5. Do not wait for human input. If blocked, make the best safe progress and leave notes in your final response.
