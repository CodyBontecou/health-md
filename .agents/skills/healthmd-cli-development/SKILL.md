---
name: healthmd-cli-development
description: Develop, debug, or extend Health.md's Mac CLI and Mac-initiated iPhone export pipeline. Use whenever the user asks to change scripts/healthmd, add CLI flags/config/API behavior, modify the localhost control server, alter Mac↔iOS export request messages, fix build issues in the CLI export path, or reason about how Mac app + CLI trigger iOS HealthKit exports.
compatibility: Requires the Health.md Xcode project and Swift/iOS/macOS build tools. Relevant files live under HealthMd/Shared/Sync, HealthMd/iOS, HealthMd/macOS/Managers, HealthMd/macOS/HealthMdApp+macOS.swift, scripts/healthmd, and docs/features/cli-mac-iphone-export.md.
---

# Health.md CLI Development

Use this skill when changing the implementation of the CLI/control-server/export-request feature from any coding-agent environment. The feature is intentionally split so the CLI stays small and the app owns sandbox, connection, HealthKit, quota, and export history.

## Agent-agnostic development rules

- Do not assume a specific assistant runtime, IDE, or proprietary command. Use ordinary file reads/edits, shell commands, Xcode/Swift tools, and equivalent JSON inspection utilities.
- Preserve machine-readable CLI behavior. Every status/export outcome should remain JSON so any agent, script, or CI job can consume it.
- Keep `scripts/healthmd` thin and predictable; substantial behavior belongs in `HealthMdCLI/` or the app-side control/sync layers.
- Prefer additive API changes. If a response or request shape must change, document compatibility and update tests instead of relying on implicit client behavior.

## Architecture

```text
scripts/healthmd
  HTTP JSON on localhost
HealthMdControlServer (macOS, 127.0.0.1:17645)
  calls MacIPhoneExportRequestCoordinator
SyncService / Multipeer
  sends iphoneExportRequest to iOS
IPhoneExportRequestHandler (iOS)
  validates HealthKit/quota/Mac readiness
  builds MacExportJob with MacExportJobBuilder
MacExportJobExecutor (macOS)
  writes files to selected Mac destination
  sends result/failure back to iOS
```

## Core files

| Area | Files |
|---|---|
| CLI package | `HealthMdCLI/` |
| Dev wrapper | `scripts/healthmd` |
| Control API | `HealthMd/macOS/Managers/HealthMdControlServer.swift` |
| Mac request lifecycle | `HealthMd/macOS/Managers/MacIPhoneExportRequestCoordinator.swift` |
| iOS request handling | `HealthMd/iOS/IPhoneExportRequestHandler.swift` |
| Sync protocol | `HealthMd/Shared/Sync/SyncPayload.swift` |
| Mac app wiring | `HealthMd/macOS/HealthMdApp+macOS.swift` |
| iOS app wiring | `HealthMd/iOS/HealthMdApp.swift` |
| Protocol tests | `HealthMdTests/Sync/SyncV2ProtocolTests.swift` |
| User/agent docs | `docs/features/cli-mac-iphone-export.md` |

## Design rules

- Keep HealthKit reads on iOS. The Mac CLI must not pretend macOS can read fresh Apple Health data.
- Keep folder writes in the Mac app. The CLI should not write export files directly because the Mac app owns sandbox bookmarks and export history.
- CLI requests default to a non-persisted `requested_dates_only` policy: keep iPhone formats/metrics/write behavior, but disable weekly/monthly/yearly roll-ups and summary-only mode for that one request. Use `current_iphone_settings` only when the user asks to mirror app settings exactly.
- Preserve the existing `MacExportJob` write pipeline. Add request/coordination behavior around it rather than duplicating exporters.
- Return structured JSON for every CLI/API outcome. Automation clients need machine-readable status, counts, destination, and failure reason.
- Use the same `jobID` across `iphoneExportRequest`, iPhone preparation progress, `macExportRequest`, and Mac final result.
- Do not log or return HealthKit sample contents through the CLI/control server.

## Control API contract

Current endpoints:

```text
GET  /v1/status
POST /v1/exports
```

Status response shape:

```json
{
  "mac_app": "running",
  "iphone": {
    "connected": true,
    "name": "Cody's iPhone",
    "can_trigger_exports": true
  },
  "destination": {
    "selected": true,
    "writable": true,
    "path": "/Users/.../Vault",
    "display_name": "Vault"
  },
  "active_export": null
}
```

Export request shape:

```json
{
  "source": "connected_iphone",
  "date_range": {"start": "2026-06-01", "end": "2026-06-07"},
  "settings_policy": "requested_dates_only",
  "response_mode": "write_files",
  "wait_timeout_seconds": 120
}
```

Use `"response_mode": "raw_json"` to return raw filtered `HealthData` records in the HTTP response without writing files. Raw mode still goes through the Mac app and connected iPhone, but skips Mac destination preflight.

Export response status values:

- `success`
- `partial_success`
- `failure`
- `cancelled`
- `unavailable`
- `timed_out`

When adding fields, prefer additive optional fields so older agents/scripts continue to work.

## Sync protocol checklist

When adding/changing Mac↔iOS messages in `SyncPayload.swift`:

1. Add a Codable case to `SyncMessage`.
2. Add or update payload structs/enums near related protocol models.
3. Add capability flags to `SyncPeerCapabilities` if older app versions need clean rejection.
4. Update both app switch statements in:
   - `HealthMd/iOS/HealthMdApp.swift`
   - `HealthMd/macOS/HealthMdApp+macOS.swift`
5. Update `HealthMdTests/Sync/SyncV2ProtocolTests.swift` round-trip coverage.
6. Build both iOS and macOS targets.

## Build and test commands

Use bounded commands. These are the minimum checks after changing this feature:

```bash
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd-macOS -configuration Debug -destination 'platform=macOS' build

xcodebuild -project HealthMd.xcodeproj -scheme HealthMd -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS -destination 'platform=macOS' -only-testing:HealthMdTests/SyncV2ProtocolTests

swift build --package-path HealthMdCLI -c release
NO_COLOR=1 TERM=dumb timeout 15 scripts/healthmd --help </dev/null
```

If touching exporters, metric mappings, units, CSV/JSON/Markdown shapes, frontmatter, or schema signatures, first read `docs/features/export-schema.md` and follow the repo's export schema contract. CLI/control API changes alone normally do not change the public export file schema.

## Common extensions

### Add CLI flags

1. Parse flags in `HealthMdCLI/Sources/healthmd/main.swift`.
2. Encode new request fields in JSON.
3. Keep `scripts/healthmd` as a thin development wrapper only.
4. Decode fields in `HealthMdControlServer.ExportRequestBody`.
5. Decide whether the Mac can satisfy it or whether iOS must receive it.
6. Add docs and a status/error example.

### Add response modes

Keep response mode separate from settings policy:

- `write_files`: default; iPhone sends `MacExportJob`; Mac writes files.
- `raw_json`: iPhone sends `IPhoneExportRawDataPayload`; Mac control server returns it under `raw_data`; no files are written.

Raw mode can expose health data in terminal output. Keep it localhost-only and do not log sample contents.

### Add settings policy support

Keep settings policies request-scoped and non-persisted. Mutating `AdvancedExportSettings()` created from `.standard` will change the user's saved iPhone settings; clone through `ExportSettingsSnapshot.from(saved).makeAdvancedExportSettings()` before applying temporary CLI overrides.

Current control API values:

- `requested_dates_only`: default for CLI; disables derived roll-ups and summary-only mode so only requested dates are fetched/written.
- `current_iphone_settings`: uses saved iPhone settings exactly, including roll-ups.

### Add config-file support

Prefer a versioned config shape:

```json
{
  "version": 1,
  "source": "connected_iphone",
  "date_range": {"type": "last_n_days", "days": 7},
  "settings": "iphone_current"
}
```

Keep settings override support separate from the first version. If config starts controlling export output, document the config schema and add compatibility tests.

### Add UI affordances

Use `MacIPhoneExportRequestCoordinator` rather than reimplementing request state. UI can observe `activeJobID` and `latestProgress`.

## Review checklist before finishing

- Both app targets build.
- Sync protocol tests cover new Codable messages or response fields.
- CLI help remains clear: `scripts/healthmd --help` and `scripts/healthmd export --help`.
- Docs explain limitations: iPhone open, HealthKit permissions, lock state, Mac destination readiness.
- Operator and QA skills still match any changed command names, flags, response fields, or failure reasons.
- No health samples are emitted by control API responses unless the user explicitly requests `raw_json`/`--raw`, and sample contents are not logged.
