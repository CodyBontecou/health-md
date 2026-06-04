# Privacy and Local-First Design

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding; Export; Sync; Schedule
- **Source files:** `README.md`, `HealthMd/Shared/Sync/SyncService.swift`, `HealthMd/Shared/Sync/SyncPayload.swift`, `HealthMd/Shared/Managers/PushRegistrationManager.swift`, `HealthMd/Shared/ExportAutomationKit/ExportAutomationScheduling.swift`, `worker/scheduled-apns-worker-contract.md` (contract only; scheduled APNs worker implementation is not present in this checkout), `HealthMd/Shared/Utilities/FeedbackHelper.swift`

## What it does

Health.md is designed around local-first health export. The app reads Apple Health on your iPhone and writes files you control: Markdown, JSON, CSV, or Obsidian Bases Markdown in a folder you choose.

Health data is not uploaded to a Health.md cloud database. Optional services exist for scheduling triggers, purchase/legacy verification, feedback, and local iPhone-to-Mac destination exports, but those systems are designed not to store HealthKit samples or vault contents on Health.md servers.

## Who it is for

- Users who want Apple Health data in plain files.
- Obsidian users who want private, local health journals.
- Users who want to understand what leaves the device.
- Users evaluating scheduled exports, Mac Destination, and support diagnostics.

## Where to find it

Privacy-relevant behavior appears across the app:

1. **Onboarding / Export** — grants HealthKit and folder access.
2. **Export** — writes local files to the chosen folder.
3. **Mac Destination** — optionally sends iPhone-configured export jobs to your Mac over the local network.
4. **Schedule** — optionally registers schedule metadata for silent push triggers.
5. **Settings → Support** — optionally sends diagnostics by email or GitHub.

## Prerequisites

- HealthKit permission must be granted before Health.md can read health samples.
- Folder access must be granted before Health.md can write exports.
- Mac Destination requires both devices nearby on local Wi‑Fi/Bluetooth and a destination folder selected on Mac.
- Scheduled exports require notification/APNs registration and schedule sync to the worker.
- Feedback requires the user to explicitly send an email or GitHub issue.

## Setup

For the most local setup:

1. Grant only the HealthKit categories you want Health.md to export.
2. Choose a local or iCloud Drive folder you control.
3. Export manually from the iPhone.
4. Leave **Mac Destination** off if you do not need desktop export.
5. Leave **Scheduled Exports** off if you do not want APNs schedule metadata registered.
6. Use feedback only when you intentionally want to contact support.

For the full workflow:

1. Enable the export formats and metrics you want.
2. Optionally enable Mac Destination for local-network desktop export.
3. Optionally enable Scheduled Exports so the worker can send silent push triggers.
4. Review Export History to confirm what ran.

## What data stays local

Health.md keeps these local to your device(s):

- HealthKit samples and summaries read from Apple Health.
- Exported Markdown, JSON, CSV, and Bases files.
- Obsidian vault contents.
- iPhone-to-Mac export jobs, which travel directly over Multipeer Connectivity.
- macOS legacy cached health records in `~/Library/Application Support/Health.md/`, only if created by older app versions.

## What may leave the device

| Feature | Data sent | Health data included? |
|---|---|---|
| Scheduled exports | APNs token, install/user ID, platform, bundle ID, optional app version/build, schedule frequency/time/weekday/timezone | No |
| Worker silent push | Silent push payload with `content-available: 1`, `type: scheduled-export`, and optional scheduled fire time | No |
| Purchase/legacy verification | StoreKit/receipt-related verification data | No exported health files |
| Feedback email/GitHub | User-written message plus diagnostics block | Only if the user manually includes it |
| Mac Destination | Export job records sent directly iPhone → Mac on local network | Yes, but not through Health.md servers |

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
```

## Tips

- Use Markdown or Obsidian Bases if you want portable files you can inspect in any text editor.
- Disable metrics you do not want exported under **Export → Health Metrics**.
- Keep your vault in a storage location that matches your privacy preference: local disk, iCloud Drive, or another provider.
- Use manual exports if you do not want schedule metadata sent to the worker.
- Use email for private support; GitHub issues are public.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Concerned scheduled exports upload health data | The worker only stores schedule/device metadata and sends silent pushes | Use manual exports, or review the Schedule docs before enabling. |
| Exported files appear in cloud storage | The chosen folder is inside iCloud Drive or another synced provider | Choose an on-device/local folder instead. |
| Connected Mac is unavailable | Mac is closed, incompatible, or has no accessible destination folder | Open/update Health.md on Mac and choose or re-select the destination folder. |
| Support message includes diagnostics | Feedback intentionally includes app/platform info | Delete the diagnostics block before sending if desired. |
| A metric appears that you do not want | Metric is enabled in Health Metrics | Disable it and re-export or delete old files manually. |
| Phone locked blocks automation | iOS protects HealthKit data while locked | Unlock before retrying or use Export History. |

## Video outline

- **Suggested title:** How Health.md Keeps Apple Health Exports Local-First
- **Hook:** “Health.md turns Apple Health into files you own without uploading your health database to a cloud service.”
- **Demo flow:**
  1. Show HealthKit permission and metric selection.
  2. Export to a local folder and open the Markdown file.
  3. Explain what Mac Destination sends locally and why Mac does not read HealthKit.
  4. Explain what Scheduled Exports send to the worker.
  5. Show feedback diagnostics and how little is included.
  6. End with recommended privacy settings.
- **Key screenshot/recording moments:** Health permissions, folder picker, generated file in Files/Obsidian, Sync toggle, Schedule toggle, diagnostics block.
- **CTA / next video:** “Next, we’ll set up Mac Destination while keeping your data on your local network.”

## Implementation notes

- Export files are written by the shared export/vault pipeline to user-selected folders.
- `SyncService` uses encrypted Multipeer Connectivity sessions for iPhone/Mac device-to-device messages.
- Mac export jobs contain device/job metadata, an iOS export settings snapshot, and `HealthData` records for the requested dates; they are used for local transfer, not server upload.
- `PushRegistrationManager` registers APNs tokens and upserts schedule metadata to the worker using the routing-only ExportAutomationKit remote schedule payloads.
- `worker/scheduled-apns-worker-contract.md` documents the scheduled APNs worker contract; the scheduled worker implementation is not present in this checkout.
- The scheduled worker should send silent APNs pushes for due schedules, advance `next_fire_at`, and compute next fire times from frequency, wall-clock time, weekday, and timezone.
- `FeedbackHelper.diagnosticsBlock` includes app version/build, platform OS version, and broad device type only.
