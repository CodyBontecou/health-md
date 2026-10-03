# Mac Destination

For exhaustive capability, request, progress, bounded-transfer, acknowledgement, rejection, and result objects, see the [Connected Mac–iPhone protocol reference](../reference/connected-mac-iphone-protocol.md).

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** iPhone → Sync → Mac Destination / Export; Mac → Mac Destination
- **Source files:** `HealthMd/Shared/Sync/SyncService.swift`, `HealthMd/Shared/Sync/SyncPayload.swift`, `HealthMd/Shared/Sync/ConnectedTransfer.swift`, `HealthMd/macOS/Managers/MacExportJobExecutor.swift`

## What it does

Mac Destination writes iPhone-configured Health.md exports into a folder selected on Mac. The iPhone remains the HealthKit source and owns dates, metrics, formats, filenames, write mode, **Lossless Health Records**, the **Write Data Dictionary** preference, and optional Markdown side effects. The Mac receives the job, writes files with shared exporters, and reports progress/results.

No HealthKit data or vault content passes through a Health.md server. Nearby transfer uses encrypted Multipeer Connectivity; Manual IP/Tailscale uses paired, encrypted Network.framework transport.

## Requirements

- Current Health.md on iPhone and Mac.
- HealthKit permission on iPhone.
- Both apps open and connected.
- A writable Mac destination folder.
- Same local network/Bluetooth, or configured Manual IP/Tailscale.

Older peers can retain legacy behavior, but current lossless and size-bounded jobs require advertised capabilities. A Mac must also advertise dictionary-preference support before accepting a job that explicitly suppresses the dictionary. Update both apps rather than accepting a silent downgrade.

## Setup

1. Open Health.md on Mac and choose your vault/root destination.
2. On iPhone, enable **Mac Destination** and connect.
3. Configure dates, metrics, formats, **Lossless Health Records**, paths, write mode, and optional side effects on iPhone.
4. Choose whether **Write Data Dictionary** should create the JSON key/unit legend.
5. Choose **Connected Mac** as target.
6. Preview, then export.

Select the equivalent vault/root on Mac. Health.md appends the iPhone's Health subfolder and templates; selecting a nested Health output folder can duplicate path components.

## Export behavior

Mac-target exports use the same schema v8, typed-provider behavior, and format roles as local iPhone exports:

- JSON contains full canonical archive when lossless capture is on;
- CSV contains canonical JSON rows;
- Markdown/Bases contain summaries and capture diagnostics/counts;
- individual entries derive from canonical records when present.

Lossless Health Records is off by default for new installs, while existing explicit on or off choices are preserved across Connected Mac exports.

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
- partitions target 48 MiB by default and negotiate within 32–64 MiB; sessions containing many small daily summaries also flush after 32 pending items so journal rewrites, UI stalls, and recovery work stay bounded;
- one dense day may span any number of partitions; physical partition/frame bounds protect transfer memory without imposing a total logical-item or corpus cap;
- each partition declares exact dates, byte count, SHA-256, sequence, and previous-partition digest, and its accepted open grants one exact transport admission; Mac binds the app-private session directory by device/inode, uses descriptor-relative no-follow source spool and journal operations, rejects rebound/symlinked directories and linked files, synchronizes the protected source files/directories, and journals each completed-file or partial-prefix digest before ACK;
- physical frame data remains capped at 512 KiB; current Multipeer peers negotiate binary frame v1 and a four-frame bounded sliding window, while older/manual-IP paths keep JSON/base64 stop-and-wait framing;
- Mac writes ordinary requested days incrementally and journals committed partition digests and exact completed dates before ACK; file-export durability is independent of the disposable encrypted query-context cache, while dedicated encrypted-context acquisitions still fail closed if their protected store cannot commit;
- corpus protocol v3 is a capability-only revision with unchanged partition bytes: compatible pinned roll-up/summary-only jobs retain all source records durably, perform no per-partition destination writes, then protect the exact selected dictionary/artifact bytes and whole-plan digest before the first destination write;
- corpus protocol v4 retains the same partition framing and public schemas while using a deterministic private `HMDCITEM` token stream for application items. Strict-raw canonical JSON moves directly from an iPhone disk spool to the item and from the received item to a checksummed Mac sidecar, avoiding a second whole-item `Data`/JSON object. Negotiated v1-v3 application bytes remain unchanged;
- v3/v4 finalization rejects more than 400 owner dates and incrementally enforces the shared semantic record/byte/batch limits instead of treating segmented transport-wrapper bytes as semantic bytes. It journals the selected-root path plus device/inode identity and a dictionary/artifact acknowledgement frontier. Production commits use descriptor-relative no-symlink traversal, canonical descriptor paths with no-follow absolute replacement, live namespace revalidation, raw-byte verification, atomic replacement, and file/directory synchronization. The non-cancellable one-file transaction spans write, exact readback, and durable frontier advancement. Relaunch resumes from protected bytes without HealthKit or either renderer, reinspects an exact durable write inside the write/readback/frontier transaction before adoption, and never rewrites an acknowledged file; negotiated v1/v2 peers keep roll-ups legacy;
- retrying the same partition is idempotent; changing a committed partition is rejected;
- aggregate corpus bytes use 64-bit counters with no 2 GiB session cap;
- available-storage checks, inactivity timeouts, cancellation, and protected-spool cleanup remain enforced.

Archive mode uses a checkpointed streaming ZIP64 writer with standard per-entry DEFLATE (method 8). CRCs remain over the original bytes, and interrupted work resumes only from fully finalized entry boundaries; legacy store-mode checkpoints continue in store mode. Mac first converts each dense day to a disk-backed aggregate-only projection, then loads one weekly/monthly/yearly window at a time across partition boundaries. Strict CLI raw uses canonical daily disk spools and a streamed checksummed loopback response rather than whole-item `JSONEncoder`/`Data` or one in-memory result object.

Mixed-version peers use the legacy single-payload protocol, which remains capped at 2 GiB and 8,192 chunks.

## Legacy cache

Older versions stored one Mac cache record per date. Current exports do not require it. **Delete Legacy Cache** removes only that cache, not Apple Health or already exported files.

## Tips

- The **menu-bar popup** (menu-bar icon → Health.md) is a compact destination agent: it shows iPhone connection status, the Mac destination folder, readiness, and the last export result, and can open full settings — without switching to the app window.

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
| Mac ran out of storage during finalization | Archive/roll-up or protected exact-plan spool cannot continue | Free destination/Application Support storage and retry; the same v3 finalization resumes from its journal. |
| Range finalization rejects after folder/file changes | The selected root was changed/rebound, protected bytes were damaged, or an already acknowledged destination file drifted | Restore the exact folder/file state or explicitly cancel and start a new export; Health.md will not redirect or rerender the pinned operation. |
| Raw status is partial | HealthKit query was incomplete on iPhone | Inspect manifest; transport success is separate from capture completeness. |

## Video outline

- **Suggested title:** Send Lossless Apple Health Exports to Your Mac Safely
- **Hook:** “Your iPhone reads HealthKit; your Mac writes the files through a bounded encrypted transfer.”
- **Demo flow:** connect/select root, export one lossless day, show progress/received formats, inspect diagnostics, and explain frame/checksum/size limits.

## Implementation notes

- `SyncService` manages encrypted Multipeer sessions and transfer acknowledgements.
- `ConnectedTransfer` carries each physical partition in 512 KiB frames; `ConnectedCorpusTransfer` defines stable sessions, negotiation, partition chains, finalization, and cancellation.
- `MacCorpusExportSessionManager` journals partition commits and applies daily items without retaining the corpus. Protected raw/source spools reconcile exact interrupted publishes, terminal journal failures restore resumable state, and setup/cleanup traverse the bound session descriptor. A strict-raw terminal result remains in an exact protected, journal-bound spool across process death and lost final acknowledgements for the fixed recovery window. Each replay revalidates or repairs the durable control-response bytes and terminal record; transient installation failures remain unacknowledged and retryable. For admitted protocol-v3 ranges the manager also owns the protected exact selected-plan spool, destination binding, per-file frontier, corruption checks, and terminal acknowledgement replay.
- `SyncPeerCapabilities` prevents unsupported peers from receiving strict jobs. Scheduled Connected Mac exports additionally require per-date completion support so retries contain only unresolved dates.
- `MacExportJob` and streamed-start metadata carry both residual daily dates and the immutable original range dates/timezone. Missing additive fields decode for backward compatibility, while range-v9 transfer is separately capability-gated from historical roll-up support. Mac does not query HealthKit. `MacExportResultPayload.completedDates` reports exact terminal days back to iPhone for residual scheduling.
- A residual ZIP retry recaptures or reuses every original-range source before rebuilding the same archive. If any original source is unavailable, finalization fails safely and preserves the existing ZIP instead of replacing it with a residual-only archive.
- Manual IP uses pairing, Curve25519 key agreement, and ChaChaPoly-encrypted frames on port `17646`.
