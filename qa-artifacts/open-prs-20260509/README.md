# QA artifacts — open PR integration (2026-05-09)

Device: iPhone 17 Pro simulator `0335EECF-93B3-4F95-9D5E-DC339BC055DB`  
Build: `HealthMd` Debug-iOS from commit `88685521`  
Launch mode: `--uitesting` with mocked Health authorization, vault selection, purchase unlock, connected sync, and schedule enabled.

## Results

| Feature | Result | Evidence |
|---|---|---|
| Mocked ready-to-export state | Pass | `00-launch-dismissed.png` |
| Manual rolling “past N days” export range | Pass — toggle exposes stepper and date range updates to the selected rolling window | `01-rolling-past-days.mp4`, `01-rolling-past-days-enabled.png`, `01-rolling-past-days-2days.png` |
| Export confirmation checkpoint | Pass — Review opens confirmation sheet with effective rolling date range, day count, formats, and file count | `02-export-confirmation.mp4`, `02-export-confirmation-summary.png` |
| Export preview entry point | Limited — Preview opens, but existing UI-test mode does not mock HealthKit sample data, so it shows “No data to preview” | `02b-export-preview-sheet.png` |
| Confirm mocked export | Pass — confirmation dismisses and simulated export success toast appears | `03-confirm-mocked-export.mp4`, `03-confirm-mocked-export-success.png` |
| Metric counter live updates | Pass — Deselect/Select All updates the summary immediately and the Export tab counter reflects the new count when returning | `04-metric-counter-live-update-select-all.mp4`, `04-metric-selection-after-deselect-all.png`, `04-metric-counter-updated-zero.png`, `04-metric-selection-after-select-all.png`, `04-metric-counter-updated-170.png` |
| Scheduled export lookback window | Pass — schedule tab shows “Export past days”; stepper updates count and explanatory footer | `05-scheduled-lookback-stepper.mp4`, `05-schedule-tab-initial.png`, `05-scheduled-lookback-3days.png` |
| Shortcuts “Export Last N Days” action discoverability | Partial/fail — action is visible under Health.md in the Shortcuts app, but tapping it in the simulator produced “Unable to run App Shortcut” | `06-shortcuts-healthmd-actions.png`, `06-shortcuts-export-last-n-days-action.mp4`, `06-shortcuts-export-last-n-days-run-result.png` |

## QA notes

- The app’s current UI-test mode mocks app readiness and export success, not real HealthKit sample payloads. That is why the preview sheet cannot display mocked health rows yet.
- The Shortcuts action discovery works, but the simulator could not run the App Shortcut from the Shortcuts app. This needs follow-up on App Intent runtime behavior outside the app/test launch environment.
