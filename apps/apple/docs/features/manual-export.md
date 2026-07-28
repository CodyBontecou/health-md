# Manual Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Managers/ExportOrchestrator.swift`, `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Manual Export immediately exports a selected date range using current metrics, formats, paths, write mode, **Lossless Health Records**, and optional roll-ups/Markdown side effects. Targets are iPhone Folder, Connected Mac, or API Endpoint.

New installs default Lossless Health Records on. An existing explicit off choice is preserved and creates summary-only v7 output.

## Setup

1. Confirm Health access and target readiness.
2. Choose iPhone Folder, Connected Mac, or API Endpoint.
3. Set start/end dates.
4. Choose Health Metrics.
5. Select Markdown, Bases, JSON, CSV, or a combination.
6. Review **Lossless Health Records**.
7. Configure roll-ups, daily-note injection, individual entries, paths, and write mode.
8. Preview one day, then export.

## Output roles

- JSON contains the authoritative canonical source archive.
- CSV contains the same canonical records as JSON rows.
- Markdown/Bases contain summaries and archive status/counts/diagnostics.
- Individual entries derive from canonical records when the archive exists.

Example:

```text
MyVault/Health/2026-07-15.md
MyVault/Health/2026-07-15-bases.md
MyVault/Health/2026-07-15.json
MyVault/Health/2026-07-15.csv
```

API target POSTs equivalent public v7 JSON records instead of writing daily files.

## Capture outcomes

A written file can contain:

- `complete`, including successful empty planned queries;
- `partial`, with retained data plus query/warning/failure diagnostics;
- `not_requested`, when lossless capture was off;
- `legacy_unavailable`, for an older stored/peer record.

Do not treat a successful write or non-empty summary as proof the source archive is complete.

## Day behavior

Canonical records belong to the day containing their source start in the captured timezone and are never clipped. Daily sleep summaries retain noon-to-noon compatibility behavior. For long/midnight-spanning events, use archive ownership.

## Roll-ups and summary-only

Roll-ups remain opt-in derived files. **Summary files only** skips daily files and daily side effects but still fetches daily aggregate snapshots for touched periods. Roll-ups do not embed canonical source archives.

## Write modes

| Mode | Behavior |
|---|---|
| Overwrite | Replace generated files. |
| Append | Append generated content. |
| Update | Merge app-managed readable Markdown sections; overwrite non-Markdown formats. |

## Practical limits

Lossless capture can include routes, waveforms, clinical documents, exact binary values, and attachments. Large ranges/files can consume substantial memory. Connected transfer frames are bounded/checksummed, but final serialization still needs resources. Start with one day and split backfills.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Export disabled | Permission/target/format/quota missing | Check badges, target, formats, and access. |
| Some dates are partial | One or more source branches failed/cancelled/skipped/unsupported | Inspect per-date manifest and retry only if appropriate. |
| No archive | Lossless off or legacy peer/data | Check status and re-export with current apps. |
| Daily value exists but individual entry is absent | Canonical event query did not return a source record | Do not substitute the summary; inspect diagnostics. |
| Large job fails | Dense/binary lossless data exhausted limits/resources | Reduce date range/formats or use summary-only. |
| Existing writing disappeared | Overwrite replaced readable Markdown | Use Update for hand-edited Markdown. |
| Daily note path conflict | Export and injection resolve to same `.md` | Change one path; Health.md blocks unsafe collision. |

## Tips

- Preview after schema v7 migration and before backfills.
- Use JSON when source completeness matters.
- Check `raw_capture_status` for every date.
- Keep v5 files as historical; re-export rather than relabel.

## Implementation notes

- `ExportOrchestrator.exportDates(...)` processes the inclusive range.
- `HealthKitManager.fetchHealthData(for:includeGranularData:metricSelection:)` builds unchanged summaries and optional canonical archive.
- Local export uses `VaultManager`; Connected Mac uses bounded `ConnectedTransfer`; API uses its independently versioned envelope containing schema-v7 daily records.
- `ExportResult` tracks file success/failure separately from source capture diagnostics.
