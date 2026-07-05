---
name: healthmd-cli-qa
description: Test and validate Health.md's Mac CLI + open-iPhone export flow. Use when the user asks to QA the CLI, verify a Mac-triggered iPhone export, test status/error paths, diagnose why scripts/healthmd export failed, prepare manual validation steps, or confirm the control server/sync protocol works across Mac and iOS builds.
compatibility: Requires macOS build tools for automated checks. Live end-to-end export requires a running Health.md Mac app, a connected/open iPhone app, HealthKit permission, and a selected writable Mac destination folder.
---

# Health.md CLI QA

Use this skill to validate the CLI/control-server feature from fast static checks through live device testing in any coding-agent environment.

## Agent-agnostic QA rules

- Use standard shell, Xcode, SwiftPM, and JSON inspection tools; do not depend on a specific assistant product or plugin.
- Keep commands bounded and non-interactive with `NO_COLOR=1 TERM=dumb`, `timeout`, and stdin redirected from `/dev/null` when invoking the CLI.
- Treat CLI JSON as the primary evidence for status, readiness, counts, destinations, and failure reasons.
- Separate automated checks from physical-device checks. If the Mac app, iPhone app, HealthKit permission, or destination folder require human action, state that clearly instead of fabricating live results.
- Save enough command/output evidence for another agent or human to reproduce the result.

## QA layers

Work from cheapest to most realistic:

1. **Static/compile checks** — protocol and app wiring compile.
2. **Protocol tests** — new messages round-trip and capability flags behave.
3. **CLI syntax checks** — Python wrapper parses commands and handles unreachable app.
4. **Mac control server smoke** — Health.md Mac app responds on localhost.
5. **Live E2E** — Mac app asks open iPhone to export and Mac writes files.

## Automated checks

Run from repo root:

```bash
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd-macOS -configuration Debug -destination 'platform=macOS' build

xcodebuild -project HealthMd.xcodeproj -scheme HealthMd -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS -destination 'platform=macOS' -only-testing:HealthMdTests/SyncV2ProtocolTests

swift build --package-path HealthMdCLI -c release
NO_COLOR=1 TERM=dumb timeout 15 scripts/healthmd --help </dev/null
```

A local machine with no running Mac app should produce a clean JSON unreachable response:

```bash
NO_COLOR=1 TERM=dumb timeout 15 scripts/healthmd status </dev/null
```

Expected shape:

```json
{
  "error": "mac_app_unreachable",
  "message": "...Connection refused..."
}
```

## Mac control server smoke test

1. Build and launch the Mac app.
2. Run:

```bash
NO_COLOR=1 TERM=dumb timeout 15 scripts/healthmd status </dev/null
```

Expected when no iPhone is connected:

- `mac_app: "running"`
- `iphone.connected: false`
- `iphone.can_trigger_exports: false`
- destination fields reflect current Mac app folder state

If status still says `mac_app_unreachable`, check:

- Mac app is the newly built version.
- No port conflict on `127.0.0.1:17645`.
- macOS app sandbox/network server entitlement is present.

## Live E2E checklist

Prerequisites:

- Run current Health.md Mac build.
- Run current Health.md iOS build on device.
- Open Health.md on iPhone.
- Enable/connect Mac Destination.
- Select a writable Mac destination folder.
- Grant HealthKit permissions on iPhone.
- Keep iPhone unlocked/open during the test.

Commands:

```bash
NO_COLOR=1 TERM=dumb timeout 15 scripts/healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 180 scripts/healthmd export --iphone --yesterday </dev/null
NO_COLOR=1 TERM=dumb timeout 180 scripts/healthmd export --iphone --yesterday --raw </dev/null
```

Pass criteria:

- Status before export has `iphone.can_trigger_exports: true`.
- Export returns `status: success` or `partial_success`.
- Response includes `job_id`, counts, and destination path/display name when available.
- Files are written under the selected Mac destination according to iPhone export formats/metrics for non-raw exports.
- Raw export returns `raw_data.records` and `files_written: 0`, and does not create files in the destination folder.
- Default CLI export does not write weekly/monthly/yearly roll-up summary files or use summary-only mode. Use `--use-iphone-settings` only when intentionally testing saved iPhone roll-up behavior.
- Mac activity/history records the export.
- iPhone export history/quota records one export action when files were written.

## Negative-path tests

Run only the relevant ones; avoid changing user settings unnecessarily.

| Scenario | Setup | Expected |
|---|---|---|
| Mac app closed | Quit Mac app | CLI status returns `mac_app_unreachable` |
| No iPhone connected | Mac app open, iPhone app closed/disconnected | export returns `unavailable` / `iphone_not_connected` |
| No Mac folder | Clear/avoid destination folder | export returns `mac_destination_unavailable` |
| Mac busy | Start one export, quickly request another | second request reports `export_in_progress` or destination busy |
| iPhone locked | Lock iPhone during request | iOS rejects/fails with HealthKit locked/fetch message |
| Free quota exhausted | Use locked/free test state if available | iOS rejects with `export_limit_reached` |
| Unsupported app version | Connect older iOS build | status cannot trigger; export reports `unsupported_iphone` |
| Raw response | Run `scripts/healthmd export --iphone --yesterday --raw` | `raw_data.records` returned, `files_written: 0`, no destination files created |
| Raw response without folder | Remove/deny Mac folder, run `--raw` | raw export can still succeed if iPhone is connected and authorized |
| Roll-ups enabled on iPhone | Enable weekly/monthly/yearly roll-ups, run default CLI export | daily requested-date files only; no roll-up summaries |
| Summary-only enabled on iPhone | Enable monthly roll-ups + summary-only, run default CLI export | daily requested-date files only; summary-only is ignored unless exact settings are requested |
| Exact iPhone settings | Enable roll-ups, run with `--use-iphone-settings` | roll-up summaries are written according to iPhone settings, including summary-only mode if enabled |

## Interpreting results

Treat the CLI JSON as source of truth, then corroborate with destination files or app history only when available. In QA notes, capture:

```text
Command:
Exit code:
JSON status:
Job ID:
Success/total:
Files written:
Destination:
Failure reason/message:
Observed files/history:
```

## Common failure investigation

### `mac_app_unreachable`

- Confirm the Mac app is running.
- Confirm it is a build containing `HealthMdControlServer`.
- Try `lsof -iTCP:17645 -sTCP:LISTEN`.

### `iphone.can_trigger_exports` false

Check status JSON in order:

1. `iphone.connected`
2. iPhone capability support
3. `destination.selected`
4. `destination.writable`
5. `active_export`

### Export times out

- Check if files were written anyway.
- Check Mac/iPhone app histories before retrying.
- Increase CLI `--timeout` for large date ranges/time-series exports.

### Partial success

Partial success can be valid when some dates have no HealthKit data. Verify counts and inspect app Export History rather than assuming the CLI failed.

## Reporting template

Use this concise report after QA:

```markdown
## Health.md CLI QA

- macOS build: pass/fail
- iOS build: pass/fail
- Sync protocol tests: pass/fail
- CLI syntax/status: pass/fail
- Live E2E: pass/fail/not run

### Result
[summary]

### Evidence
- command/output snippets
- destination files/history notes

### Follow-ups
- [ ] item
```
