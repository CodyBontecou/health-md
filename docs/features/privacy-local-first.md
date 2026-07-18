# Privacy and Local-First Design

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding; Export; Sync; Schedule
- **Source files:** `HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift`, `HealthMd/Shared/Sync/ConnectedTransfer.swift`, `HealthMd/Shared/Sync/SyncService.swift`, `HealthMd/Shared/Managers/HealthKitSafeLogging.swift`, `HealthMd/Shared/Managers/PushRegistrationManager.swift`, `worker/src/scheduled.ts`

## What it does

Health.md is local-first. The iPhone reads public HealthKit/WorkoutKit APIs and writes files you control. Schema v7 can retain exact source UUIDs/timestamps, provenance, typed metadata, clinical data, routes, ECG waveforms, medications, and available binary attachments when **Lossless Health Records** is on, so those files should be protected like the original health database.

Health data is not uploaded to a Health.md cloud database. Optional services exist for scheduling triggers, purchase/legacy verification, feedback, encrypted local iPhone-to-Mac transfer, user-configured API uploads, and WHOOP OAuth. API Endpoint is intentionally different: it sends selected daily JSON, including the canonical archive when enabled, to the endpoint you choose.

## Who it is for

- Users who want Apple Health data in plain files.
- Obsidian users who want private, local health journals.
- Users who want to understand what leaves the device.
- Users evaluating scheduled exports, Mac Destination, and support diagnostics.

## Where to find it

Privacy-relevant behavior appears across the app:

1. **Onboarding / Export:** grants HealthKit and folder access.
2. **Export:** writes local files to the chosen folder.
3. **Mac Destination:** optionally sends iPhone-configured export jobs to your Mac over the local network.
4. **API Endpoint:** optionally POSTs selected Health.md JSON records to your configured endpoint.
5. **Schedule:** optionally registers schedule metadata for silent push triggers.
6. **Settings → Connected Apps:** optionally authorizes WHOOP and exports provider sidecars when the staged rollout is enabled.
7. **Settings → Support:** optionally sends diagnostics by email or GitHub.

## Prerequisites

- HealthKit permission must be granted before Health.md can read health samples.
- Folder access must be granted before Health.md can write exports.
- Mac Destination requires both devices nearby on local Wi‑Fi/Bluetooth and a destination folder selected on Mac.
- Scheduled exports require notification/APNs registration and schedule sync to the worker.
- API Endpoint export requires a user-entered HTTP(S) URL and optional token.
- WHOOP requires explicit OAuth consent. Its client secret remains in the OAuth broker, while access and rotating refresh tokens remain in iOS Keychain.
- Feedback requires the user to explicitly send an email or GitHub issue.

## Setup

For the most local setup:

1. Grant only the HealthKit categories you want Health.md to export.
2. Choose a local or iCloud Drive folder you control.
3. Export manually from the iPhone.
4. Leave **Mac Destination** off if you do not need desktop export.
5. Leave **API Endpoint** unconfigured unless you intentionally want to upload selected health data to your own service.
6. Leave **Scheduled Exports** off if you do not want APNs schedule metadata registered.
7. Leave **Connected Apps** disconnected if you do not want WHOOP data fetched and written as sidecars.
8. Use feedback only when you intentionally want to contact support.

For the full workflow:

1. Enable the export formats and metrics you want.
2. Optionally enable Mac Destination for local-network desktop export.
3. Optionally enable Scheduled Exports so the worker can send silent push triggers.
4. Review Export History to confirm what ran.

## What data stays local

Health.md keeps these local to your device(s):

- HealthKit summaries and canonical source records read from Apple Health.
- Exact captured binary values and attachments, base64-encoded in JSON/CSV with checksums when available.
- Exported Markdown, JSON, CSV, Bases, and individual-entry files.
- Obsidian vault contents.
- iPhone-to-Mac export jobs, which use encrypted, checksum-validated, size-bounded partitions inside a stable corpus session.
- macOS legacy cached health records in `~/Library/Application Support/Health.md/`, only if created by older app versions.
- WHOOP access and rotating refresh tokens, which are stored in iOS Keychain. The OAuth broker does not retain them.

## What may leave the device

| Feature | Data sent | Health data included? |
|---|---|---|
| Scheduled exports | APNs token, install/user ID, platform, bundle ID, schedule frequency/time/weekday/timezone | No |
| Worker silent push | Push payload with `type: scheduled-export`, fire time, schedule version | No |
| Purchase/legacy verification | StoreKit/receipt-related verification data | No exported health files |
| Feedback email/GitHub | User-written message plus diagnostics block | Only if the user manually includes it |
| Mac Destination | Selected summaries and canonical records sent directly iPhone → Mac over encrypted partitioned transfer | Yes, but not through Health.md servers |
| API Endpoint | `healthmd.api_export` daily v7 JSON, including lossless records/binary data when enabled, sent directly iPhone → configured endpoint | Yes, to the endpoint you choose |
| WHOOP OAuth broker | Provider/client IDs, redirect URI, OAuth code exchange, and token refresh in transit; no retained provider tokens or records | No WHOOP health records |
| WHOOP API | Read-only cycle, recovery, sleep, workout, and current body profile requests sent directly iPhone → WHOOP | Yes, from WHOOP to the iPhone |

## Example local file paths

Manual iPhone export to a selected vault:

```text
MyVault/Health/2026-05-12.md
MyVault/Health/2026-05-12.json
MyVault/Health/2026-05-12.csv
```

Mac destination export:

```text
MacVault/Health/2026-05-12.md
MacVault/Health/2026-05-12.json
MacVault/Health/integrations/whoop/2026-05-12.json
```

API endpoint export:

```text
POST https://api.example.com/healthmd/ingest
```

## Data boundaries and limits

- Health.md uses public APIs only. It does not infer unavailable sleep schedules, ECG leads, blood-pressure sessions, or private Apple fields.
- HealthKit can make denied read access look successfully empty; Health.md cannot bypass that privacy behavior.
- Current exports are snapshots and do not contain historical deletion tombstones.
- Source URLs are preserved as values but never fetched or followed.
- Clinical query logging omits localized descriptions/user info that could contain PHI.
- Canonical JSON/CSV can be large and final serialization can use substantial memory. Bounded Mac frames prevent unbounded transport messages, not large final files.

## Tips

- Treat lossless JSON/CSV and individual entries as sensitive source health records.
- Disable metrics you do not want exported and opt into medications/vision/documents deliberately.
- Keep your vault in a storage location matching your privacy preference.
- Use manual exports if you do not want schedule metadata sent to the worker.
- Use API Endpoint only with services you control or trust; prefer HTTPS and apply retention/access controls.
- Do not automatically fetch preserved source URLs downstream.
- Use email for private support; GitHub issues are public.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Concerned scheduled exports upload health data | The worker only stores schedule/device metadata and sends silent pushes | Use manual exports, or review the Schedule docs before enabling. |
| Exported files appear in cloud storage | The chosen folder is inside iCloud Drive or another synced provider | Choose an on-device/local folder instead. |
| Connected Mac is unavailable | Mac is closed, incompatible, or has no accessible destination folder | Open/update Health.md on Mac and choose or re-select the destination folder. |
| Support message includes diagnostics | Feedback intentionally includes app/platform info | Delete the diagnostics block before sending if desired. |
| API endpoint stores health data | API exports are sent directly to the configured service | Review that service's logs, retention, and privacy behavior before using it. |
| A metric appears that you do not want | Metric is enabled in Health Metrics | Disable it and re-export or delete old files manually. |
| API payload contains clinical/binary details | Lossless Health Records is enabled | Turn it off for summary-only uploads or secure the receiving service appropriately. |
| Query is empty despite known data | HealthKit may hide denied read access | Review Apple Health permissions; Health.md cannot distinguish all denial states. |
| WHOOP data is missing | The day has no score/data, a scope was not granted, access was revoked, or WHOOP rate limited the request | Review the sidecar error, retry after the reset window, or reconnect WHOOP and approve every requested scope. |
| Phone locked blocks automation | iOS protects HealthKit data while locked | Unlock before retrying or use Export History. |

## Video outline

- **Suggested title:** How Health.md Keeps Apple Health Exports Local-First
- **Hook:** “Health.md turns Apple Health into files you own without uploading your health database to a cloud service.”
- **Demo flow:**
  1. Show HealthKit permission and metric selection.
  2. Export to a local folder and open the Markdown file.
  3. Explain what Mac Destination sends locally and why Mac does not read HealthKit.
  4. Explain API Endpoint export and why it should only point to a trusted service.
  5. Explain what Scheduled Exports send to the worker.
  6. Show feedback diagnostics and how little is included.
  7. End with recommended privacy settings.
- **Key screenshot/recording moments:** Health permissions, folder picker, generated file in Files/Obsidian, Sync toggle, Schedule toggle, diagnostics block.
- **CTA / next video:** “Next, we’ll set up Mac Destination while keeping your data on your local network.”

## Implementation notes

- Export files are written by the shared export/vault pipeline to user-selected folders.
- `HealthKitRecordArchiveSerializer` deterministically base64-encodes typed binary values; attachment capture adds SHA-256 when bytes are available.
- `SyncService` uses encrypted Multipeer sessions; `ConnectedTransfer` adds bounded chunks, acknowledgements, temporary files, SHA-256 validation, and cleanup.
- Mac export jobs contain device/job metadata, an iOS settings snapshot, and requested `HealthData`; they are local transfer only.
- `HealthKitSafeLogging` keeps clinical failure logs to type/domain/code rather than PHI-bearing localized text.
- API Endpoint export sends a `healthmd.api_export` envelope directly to the configured endpoint with public `healthmd.health_data` JSON records for successful days and optional schema-v1 WHOOP sidecars.
- The OAuth broker exchanges WHOOP codes and rotating refresh tokens without retaining them or proxying WHOOP health data. Provider tokens are stored in iOS Keychain, and sidecar encoding redacts OAuth secrets and pagination cursors.
- `PushRegistrationManager` registers APNs tokens and upserts schedule metadata to the worker.
- `worker/src/scheduled.ts` sends silent APNs pushes for due schedules and advances `next_fire_at`.
- `worker/src/scheduling.ts` computes next fire times from frequency, wall-clock time, weekday, and timezone.
- `FeedbackHelper.diagnosticsBlock` includes app version/build, platform OS version, and broad device type only.
