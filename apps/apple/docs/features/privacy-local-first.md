# Privacy and Local-First Design

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding; Export; Sync; Schedule
- **Source files:** `HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift`, `HealthMd/Shared/Sync/ConnectedTransfer.swift`, `HealthMd/Shared/Sync/SyncService.swift`, `HealthMd/Shared/Managers/HealthKitSafeLogging.swift`, `HealthMd/Shared/Managers/PushRegistrationManager.swift`, `worker/src/scheduled.ts`

## What it does

Health.md does not collect or store users' health data on Health.md servers. The iPhone reads public
HealthKit and WorkoutKit APIs only after permission, then writes or transfers the selected export to
a destination the user chooses. An experimental hosted account and synchronization path was removed
before deployment: no production endpoint or production OAuth client was provisioned, and it
accepted no user health data. There is no legacy Health.md-hosted corpus to migrate or delete.

Schema v7 can retain exact source UUIDs and timestamps, provenance, typed metadata, routes, ECG
waveforms, medications, and available binary attachments when **Lossless Health Records** is on.
Those destination files should be protected like the original health database. The schema can decode
historical clinical records, but current App Store builds do not request or capture them.

Health data can leave the iPhone only through an explicit user-directed destination: an export folder
or file provider, encrypted direct transfer to a paired Mac or CLI, a user-configured API endpoint,
or a connected provider request. Health.md does not keep a second server copy for later queries.
Optional scheduling, purchase verification, feedback, and campaign services handle only the limited
non-health metadata described below.

## Who it is for

- Users who want Apple Health data in plain files.
- Obsidian users who want private health journals.
- Users who want to understand what leaves the device.
- Users evaluating scheduled exports, Mac Destination, API Endpoint, and support diagnostics.

## Where to find it

Privacy-relevant behavior appears across the app:

1. **Onboarding / Export:** grants HealthKit and folder access.
2. **Export:** writes selected files to the chosen folder or file provider.
3. **Mac Destination:** sends an iPhone-configured export directly to a paired Mac.
4. **Direct CLI Access:** answers a bounded request from an explicitly paired command over the encrypted direct protocol.
5. **API Endpoint:** POSTs selected Health.md JSON records directly to the configured endpoint.
6. **Schedule:** registers non-health schedule and device-delivery metadata for silent push triggers.
7. **Settings → Connected Apps:** authorizes supported providers and writes provider sidecars when enabled.
8. **Settings → Support:** sends a message only after the user chooses email or GitHub.

## Prerequisites

- HealthKit permission must be granted before Health.md can read health samples.
- Folder access must be granted before Health.md can write exports.
- Mac Destination requires an approved device connection and a destination folder selected on Mac.
- Direct CLI Access requires explicit pairing and an open iPhone when work starts.
- Scheduled exports require notification/APNs registration and schedule sync to the worker.
- API Endpoint requires a user-entered HTTP(S) URL and optional credential.
- Connected provider access requires explicit provider authorization.
- Feedback requires the user to send an email or GitHub issue.

## Setup

For the most local setup:

1. Grant only the HealthKit categories you want Health.md to export.
2. Choose an on-device folder you control.
3. Export manually from the iPhone.
4. Leave **Mac Destination** and **Direct CLI Access** off if you do not need them.
5. Leave **API Endpoint** unconfigured unless you intend to send selected data to your own service.
6. Leave **Scheduled Exports** off if you do not want APNs schedule metadata registered.
7. Leave **Connected Apps** disconnected if you do not want provider data fetched.
8. Use feedback only when you intend to contact support.

For a broader workflow, enable only the formats, metrics, destinations, and integrations you need,
then use Export History to confirm what ran.

## What stays on user-controlled devices or destinations

- HealthKit summaries and source records read from Apple Health.
- Captured binary values and attachments included in selected lossless exports.
- Exported Markdown, JSON, CSV, Bases, and individual-entry files.
- Obsidian vault contents.
- Direct iPhone-to-Mac and iPhone-to-CLI transfer spools and durable job state.
- Legacy macOS cached records in `~/Library/Application Support/Health.md/`, if an older version created them.
- Connected-provider access and refresh tokens stored in iOS Keychain.

Files placed in iCloud Drive, Dropbox, Google Drive, another file provider, an Obsidian sync service,
or a user-configured API belong to that destination and follow its retention and privacy controls.
Health.md does not control or silently delete those destination copies.

## What may leave the device

| Feature | Data sent | Health data included? |
|---|---|---|
| Scheduled exports | APNs token, install/user ID, platform, bundle ID, schedule frequency/time/weekday/timezone | No |
| Worker silent push | Push type, fire time, and schedule version | No |
| Purchase/legacy verification | StoreKit or receipt verification data | No exported health files |
| Feedback email/GitHub | User-written message plus a bounded diagnostics block | Only if the user includes it |
| Mac Destination | Selected summaries and records sent directly iPhone → Mac over encrypted transfer | Yes, not through Health.md servers |
| Direct CLI Access | Bounded queries or selected exports sent directly to the paired CLI | Yes, not through Health.md servers |
| API Endpoint | Selected `healthmd.api_export` JSON sent directly to the configured endpoint | Yes, to the endpoint the user chooses |
| Connected-provider OAuth broker | Provider/client IDs, redirect URI, code exchange, and token refresh in transit | No provider health records retained by the broker |
| Connected-provider API | Read-only requests sent between the iPhone and the selected provider | Yes, from the provider to the iPhone |

## Example destination paths

Manual iPhone export:

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

User-configured API export:

```text
POST https://api.example.com/healthmd/ingest
```

## Data boundaries and limits

- Health.md uses public APIs only. It does not infer unavailable sleep schedules, ECG leads, blood-pressure sessions, or private Apple fields.
- HealthKit can make denied read access look successfully empty; Health.md cannot bypass that behavior.
- Current exports are snapshots and do not contain historical deletion tombstones.
- Preserved source URLs are values and are never fetched or followed by Health.md.
- Clinical query logging omits localized descriptions and user info that could contain health data.
- Canonical JSON/CSV can be large. Bounded direct-transfer frames prevent unbounded messages, not large final destination files.
- A user-operated direct relay and its supporting services must not log health payloads, export content, destination paths, or direct-query results.

## Tips

- Treat lossless JSON/CSV and individual entries as sensitive source records.
- Disable metrics you do not want exported and opt into medications, vision, and documents deliberately.
- Choose a storage location matching your privacy preference.
- Use manual exports if you do not want schedule metadata sent to the worker.
- Use API Endpoint only with services you control or trust; prefer HTTPS and configure retention and access controls there.
- Do not automatically fetch preserved source URLs downstream.
- Use email for private support; GitHub issues are public.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Concerned scheduled exports upload health data | The worker stores schedule/device metadata and sends silent pushes, not health payloads | Use manual exports or disable scheduling. |
| Exported files appear in cloud storage | The chosen folder is inside iCloud Drive or another synced provider | Choose an on-device/local folder instead. |
| Connected Mac is unavailable | Mac is closed, incompatible, or has no accessible destination folder | Open or update Health.md on Mac and reselect the destination. |
| Support message includes diagnostics | Feedback intentionally includes bounded app/platform information | Delete the diagnostics block before sending. |
| API endpoint stores health data | Exports are sent directly to the configured service | Review that service's logs, retention, access, and deletion controls. |
| A metric appears that you do not want | The metric is enabled in Health Metrics | Disable it and re-export or delete prior destination files. |
| API payload contains clinical or binary details | Lossless Health Records is enabled | Disable it for summary-only exports or secure the receiving service. |
| Query is empty despite known data | HealthKit may hide denied read access | Review Apple Health permissions. |
| Connected-provider data is missing | Data, scope, authorization, or provider rate limits may be unavailable | Review the sidecar error or reconnect the provider. |
| Phone locked blocks automation | iOS protects HealthKit data while locked | Unlock before retrying or review Export History. |

## Video outline

- **Suggested title:** How Health.md Keeps Apple Health Exports Local-First
- **Hook:** “Health.md does not store your health data; you choose every destination.”
- **Demo flow:**
  1. Show HealthKit permission and metric selection.
  2. Export to a local folder and open the Markdown file.
  3. Explain direct Mac and CLI transfer.
  4. Explain that API Endpoint sends data to the service the user configured.
  5. Explain that scheduling sends non-health trigger metadata.
  6. Show the bounded feedback diagnostics block.
- **Key screenshot/recording moments:** Health permissions, folder picker, generated file, Sync controls, Schedule toggle, diagnostics block.
- **CTA / next video:** “Next, we’ll set up Mac Destination while keeping transfer on your local connection.”

## Implementation notes

- Export files use the shared export/vault pipeline and user-selected folders.
- `HealthKitRecordArchiveSerializer` deterministically base64-encodes typed binary values; attachment capture adds SHA-256 when bytes are available.
- `SyncService` uses encrypted sessions; `ConnectedTransfer` adds bounded chunks, acknowledgements, temporary files, SHA-256 validation, and cleanup.
- Mac export jobs are direct transfer only.
- `HealthKitSafeLogging` restricts clinical failures to type/domain/code rather than health-bearing localized text.
- API Endpoint sends a `healthmd.api_export` envelope directly to the configured endpoint.
- Provider OAuth brokers exchange codes or refresh credentials without retaining provider health records; provider tokens remain in iOS Keychain.
- `PushRegistrationManager` registers APNs tokens and schedule metadata. Custom interval details remain on device where documented.
- `worker/src/scheduled.ts` sends silent APNs pushes for due schedules and advances `next_fire_at`.
- `FeedbackHelper.diagnosticsBlock` contains app version/build, OS version, and broad device type only.
