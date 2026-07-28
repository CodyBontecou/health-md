# Mac Destination

For exhaustive capability, request, progress, bounded-transfer, acknowledgement, rejection, and result objects, see the [Connected Mac–iPhone protocol reference](../reference/connected-mac-iphone-protocol.md).

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** iPhone → Mac Destination / Export; Mac → Mac Destination
- **Source files:** `HealthMd/Shared/Sync/SyncService.swift`, `HealthMd/Shared/Sync/SyncPayload.swift`, `HealthMd/Shared/Sync/ConnectedTransfer.swift`, `HealthMd/macOS/Managers/MacExportJobExecutor.swift`

## What it does

Mac Destination writes iPhone-configured Health.md exports into a folder selected on Mac. The iPhone remains the HealthKit source and owns dates, metrics, formats, filenames, write mode, **Lossless Health Records**, and optional Markdown side effects. The Mac receives the job, writes files with shared exporters, and reports progress/results.

No HealthKit data or vault content passes through a Health.md server. Nearby transfer uses encrypted Multipeer Connectivity; Manual IP/Tailscale uses paired, encrypted Network.framework transport.

## Requirements

- Current Health.md on iPhone and Mac.
- HealthKit permission on iPhone.
- Both apps open and connected.
- A writable Mac destination folder.
- Same local network/Bluetooth, or configured Manual IP/Tailscale.

Older peers can retain legacy behavior, but current lossless and size-bounded jobs require advertised capabilities. Update both apps rather than accepting a silent downgrade.

## Setup

1. Open Health.md on Mac and choose your vault/root destination.
2. On iPhone, enable **Mac Destination** and connect.
3. Configure dates, metrics, formats, **Lossless Health Records**, paths, write mode, and optional side effects on iPhone.
4. Choose **Connected Mac** as target.
5. Preview, then export.

Select the equivalent vault/root on Mac. Health.md appends the iPhone's Health subfolder and templates; selecting a nested Health output folder can duplicate path components.

## Export behavior

Mac-target exports use the same schema v7 and format roles as local iPhone exports:

- JSON contains full canonical archive when lossless capture is on;
- CSV contains canonical JSON rows;
- Markdown/Bases contain summaries and capture diagnostics/counts;
- individual entries derive from canonical records when present.

Lossless Health Records is on by default for new installs, while an existing explicit off choice remains summary-only.

Example:

```text
MyVault/Health/2026-07-15.md
MyVault/Health/2026-07-15-bases.md
MyVault/Health/2026-07-15.json
MyVault/Health/2026-07-15.csv
```

## Partitioned connected transfer

Current peers use one stable, durable corpus session instead of preparing a whole job:

- iPhone captures and encodes one day at a time, then releases it from memory;
- partitions target 48 MiB by default and negotiate within 32–64 MiB;
- one dense day may span any number of partitions; physical partition/frame bounds protect transfer memory without imposing a total logical-item or corpus cap;
- each partition declares exact dates, byte count, SHA-256, sequence, and previous-partition digest, and its accepted open grants one exact transport admission;
- physical frame data remains capped at 512 KiB; current Multipeer peers negotiate binary frame v1 and a four-frame bounded sliding window, while older/manual-IP paths keep JSON/base64 stop-and-wait framing;
- Mac writes complete requested days incrementally and journals committed partition digests and exact completed dates before ACK;
- retrying the same partition is idempotent; changing a committed partition is rejected;
- aggregate corpus bytes use 64-bit counters with no 2 GiB session cap;
- available-storage checks, inactivity timeouts, cancellation, and protected-spool cleanup remain enforced.

Archive mode uses a checkpointed streaming ZIP64 writer. Mac first converts each dense day to a disk-backed aggregate-only projection, then loads one weekly/monthly/yearly window at a time across partition boundaries. Strict CLI raw uses daily spools and a streamed checksummed loopback response rather than one in-memory JSON object.

Mixed-version peers use the legacy single-payload protocol, which remains capped at 2 GiB and 8,192 chunks.

## Legacy cache

Older versions stored one Mac cache record per date. Current exports do not require it. **Delete Legacy Cache** removes only that cache, not Apple Health or already exported files.

## Tips

- Keep both apps foregrounded and devices nearby during large jobs.
- Start with one lossless day to verify permissions/paths, then use a multi-year partitioned backfill.
- Use Preview to check paths and formats.
- Use Update for readable Markdown you edit by hand.
- Review `raw_capture_status` in received files; successful transport does not turn partial HealthKit capture into complete capture.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No Mac connected | Mac closed/not browsing/network unavailable | Open Mac app and verify local network/Bluetooth or Manual IP. |
| Connected Mac disabled | Folder/capability/version/busy state is not ready | Check Mac Destination status and update both apps. |
| Folder access denied | Security-scoped bookmark is stale | Re-select the Mac folder. |
| Duplicated path | Mac destination points inside Health output | Select the vault/root instead. |
| Transfer rejected before sending | Peer lacks partitioned capability, storage, or required archive version | Update both apps and free space on both devices. |
| Checksum/sequence/inactivity failure | Connection or partition integrity failed | Keep apps open; Health.md retries the same partition, or reconnect and retry the request. |
| Mac ran out of storage during finalization | Archive/roll-up spool cannot continue | Free destination/Application Support storage and retry. |
| Raw status is partial | HealthKit query was incomplete on iPhone | Inspect manifest; transport success is separate from capture completeness. |

## Video outline

- **Suggested title:** Send Lossless Apple Health Exports to Your Mac Safely
- **Hook:** “Your iPhone reads HealthKit; your Mac writes the files through a bounded encrypted transfer.”
- **Demo flow:** connect/select root, export one lossless day, show progress/received formats, inspect diagnostics, and explain frame/checksum/size limits.

## Implementation notes

- `SyncService` manages encrypted Multipeer sessions and transfer acknowledgements.
- `ConnectedTransfer` carries each physical partition in 512 KiB frames; `ConnectedCorpusTransfer` defines stable sessions, negotiation, partition chains, finalization, and cancellation.
- `MacCorpusExportSessionManager` journals partition commits and applies daily items without retaining the corpus.
- `SyncPeerCapabilities` prevents unsupported peers from receiving strict jobs. Scheduled Connected Mac exports additionally require per-date completion support so retries contain only unresolved dates.
- `MacExportJob` carries iPhone settings and per-date HealthData; Mac does not query HealthKit. `MacExportResultPayload.completedDates` reports exact terminal days back to iPhone for residual scheduling.
- Manual IP uses pairing, Curve25519 key agreement, and ChaChaPoly-encrypted frames on port `17646`.
