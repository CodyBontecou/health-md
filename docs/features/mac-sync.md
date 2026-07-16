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

Mac-target exports use the same schema v6 and format roles as local iPhone exports:

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

## Bounded connected transfer

Current peers use a versioned streaming protocol instead of sending an unbounded whole job:

- payload is prepared as a temporary file;
- maximum frame/chunk data is 512 KiB;
- maximum chunk count is 8,192;
- maximum declared transfer size is 2 GiB;
- receiver validates sequence, declared size, and SHA-256 before decoding;
- each start/chunk/completion is acknowledged with retry/inactivity limits;
- cancellation, disconnect, invalid manifest, checksum mismatch, and storage failures abort and clean up.

These bounds protect the transport and avoid base64-wrapping the complete payload. They do not guarantee small files or low memory use. The iPhone still captures records and the final Mac exporter can use substantial memory while building JSON/CSV. Export fewer days for dense routes, ECGs, clinical documents, or attachments.

Strict CLI raw results use the same bounded transfer capability and never downgrade to a whole raw payload.

## Legacy cache

Older versions stored one Mac cache record per date. Current exports do not require it. **Delete Legacy Cache** removes only that cache, not Apple Health or already exported files.

## Tips

- Keep both apps foregrounded and devices nearby during large jobs.
- Start with one lossless day before a backfill.
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
| Transfer rejected before sending | Peer lacks bounded transfer capability or declared job exceeds limits | Update both apps and reduce the range. |
| Checksum/sequence/inactivity failure | Connection or transfer integrity failed | Reconnect, keep apps open, retry fewer days. |
| Mac ran out of resources after transfer | Final lossless serialization is large | Reduce dates/formats or disable lossless capture if summaries suffice. |
| Raw status is partial | HealthKit query was incomplete on iPhone | Inspect manifest; transport success is separate from capture completeness. |

## Video outline

- **Suggested title:** Send Lossless Apple Health Exports to Your Mac Safely
- **Hook:** “Your iPhone reads HealthKit; your Mac writes the files through a bounded encrypted transfer.”
- **Demo flow:** connect/select root, export one lossless day, show progress/received formats, inspect diagnostics, and explain frame/checksum/size limits.

## Implementation notes

- `SyncService` manages encrypted Multipeer sessions and transfer acknowledgements.
- `ConnectedTransfer` defines manifest/start/chunk/ack/complete/abort, temporary-file streaming, bounds, SHA-256, and cleanup.
- `SyncPeerCapabilities` prevents unsupported peers from receiving strict jobs.
- `MacExportJob` carries iPhone settings and per-date HealthData; Mac does not query HealthKit.
- Manual IP uses pairing, Curve25519 key agreement, and ChaChaPoly-encrypted frames on port `17646`.
