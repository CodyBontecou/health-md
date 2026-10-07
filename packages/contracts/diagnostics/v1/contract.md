# Local diagnostics v1

## Outcome and boundary

On iPhone/iPad, macOS, and Android, a user can inspect local technical events,
choose a time range/subsystem/operation, optionally include recorded private
context, attach any existing original files (including health exports), and
review a frozen ZIP before explicitly saving or sharing it. No diagnostic
uploads, new health reads, credential-store access, OSLog/logcat harvesting,
analytics forwarding, or protocol messages are introduced.

These independent schemas are `healthmd.diagnostic_event` / 1 and
`healthmd.diagnostic_bundle` / 1. They do not change health export profiles,
`HealthMdExportSchema.version`, Direct protocol versions, clinical services,
Workers, or CLI/Obsidian health-data inputs. Native apps produce these bundles;
ZIP/JSON tools are the initial consumers. Rust/CLI and Obsidian do not currently
consume the diagnostic contract.

Authorities:

- [catalog.json](catalog.json): event IDs, severity, subsystem, field type and privacy.
- [event.schema.json](event.schema.json): closed published event shape.
- [bundle.schema.json](bundle.schema.json): closed published manifest shape.
- [privacy fixture](fixtures/privacy.json): synthetic Swift/Kotlin projection vector.

Run `python3 packages/contracts/diagnostics/generate.py --check` from the repository
root. The catalog generates native validators and both schemas. Unknown fields
must never acquire operational classification by default. Once shipped, changing
closed shapes or promoting sensitivity requires a reviewed contract version.

## Recording and privacy

Recording is local and enabled at Debug by default. Info/Debug/Trace control
verbosity, not permission to capture health content. Global disable preserves
existing records; clearing stops private recording and deletes stored diagnostics,
not original attachments or copies already exported. New operational recording
keeps its existing enable setting after clearing.

Fields are catalog-validated before persistence and projected again when read or
shared. There is no arbitrary message, exception-description, `userInfo`, provider
response, preference, history, URL, path, metric-selection, requested-health-date,
health-measurement or health-record-ID field. Operational fields are finite enums,
booleans, bounded integers/counts, random job UUIDs, and session-local peer aliases.
Do not bind a health-record identifier or measured health value to an operational
field merely because its primitive type fits.

V1 private context is limited to peer names (512 UTF-8 bytes). Its recording is a
separate explicit 15-minute opt-in, checked at admission and persistence. A
monotonic deadline prevents extending an active session by moving the wall clock
backward. A valid remaining wall-clock expiry is restored on app restart; an
expiry more than 15 minutes into the future is rejected. It never enables health
payload or credential capture. Opting in later does not recover unrecorded names.
Sharing recorded names is a separate, default-off choice. Free-form names and
attachments may incidentally contain personal, health, or secret information.

Operational-only is **not anonymous**: timing, app/OS version, job IDs, counters,
error codes, connection behavior, and usage patterns remain. Known native error
domains/categories and numeric codes are retained, but arbitrary exception text
and unknown domain strings are not. `unknown` is not proof of a particular cause.

## Event semantics

Each event carries a stable event ID, catalog severity/subsystem, UTC timestamp
with milliseconds, per-process random session UUID, sequence, process-relative
monotonic milliseconds, platform, public code file/line, fields, and omissions.
Timestamps/monotonic time describe recorder admission, not later disk completion.
Sequence is persistence order. Across devices, wall clocks may differ; aliases
and session counters are not global identities. `operation_id` is an existing
random operational job/request identifier, never a health-record identifier.
Source `:0` means a source line was unavailable.

Omissions distinguish:

- `not_recorded`: recording permission was absent/expired; no stored value exists.
- `redacted`: a previously recorded private value was excluded from this projection.
- `unavailable`: the producer could not observe this field.
- `truncated`: only partial detail was available (not a permission denial).
- `invalid`: the catalog rejected its type/value.

Fields and omissions must be disjoint. Unsupported events/metadata are omitted
and counted as invalid; unknown keys are never echoed. Duplicate session/sequence
identities are excluded and counted. Snapshots contain the newest 10,000 selected
valid events in timestamp/session/sequence order and disclose truncation.

A successful notification request means only native API admission, **not** actual
display. Native lifecycle callbacks are explicit `native_callback` values, not
inferred suspension or permission outcomes. A WorkManager result describes worker
completion/retry, not health export completeness. `schedule.background_expired`
is the expiration callback, not a claim the OS has already suspended the app.
Nearby start/stop events observe API calls, not confirmed radio advertising.
`ready` is the emitting
connection service's observed readiness, not proof of health permission.

## Storage and missingness

- Operational segments: at most seven days; private segments: at most 24 hours.
- Combined segment budget: 20 MiB; individual segments: at most 1 MiB; event: 16 KiB.
- Bounded nonblocking write admission: 128 queued/pending writes; drops disclosed.
- Cleanup runs on recorder initialization, writes and snapshots. Expired segments
  are excluded even if physical deletion fails. Local expiry is enforced on next
  app access, not by a guaranteed background timer.
- Prepared local directories: expire after 24 hours on access, at most three
  newest directories. Prepared archives/copies have a separate budget derived
  from the 100 MiB attachment cap and duplicated readable event files; they are
  **not** counted in the 20 MiB segment limit.
- Drop counts cover this process only (admission/storage failures); they cannot
  prove completeness of previous sessions. Rotation/expiry and user-selected
  filters intentionally remove records; absence is not proof nothing happened.

Apple uses app-private Application Support, restrictive permissions and backup
exclusion. iOS segments use complete-until-first-authentication protection;
prepared bundle files use complete protection. macOS uses filesystem permissions
and an exclusion flag; this does not promise exclusion from arbitrary third-party
backup software. Android uses `noBackupFilesDir`; final shared ZIP copies alone
are exposed through a narrow, nonexported FileProvider cache path and read grants.
Clearing Android diagnostics also clears app-owned sharing copies. Saved/shared
copies elsewhere cannot be recalled.

## Frozen bundle

```text
healthmd-diagnostics.zip
├── manifest.json
├── README.txt
├── events.jsonl
├── events.txt
└── attachments/attachment-1.<safe-extension>  # optional
```

The manifest inventories every content file except itself, with relative path,
byte count, SHA-256, privacy, optional original name, and filename truncation flag.
It includes build/OS context, selections, event count, current-process drops,
invalid count, truncation and sensitivity. ZIP paths are generated, never taken
from source filenames. Filenames longer than 512 characters are disclosed as
truncated; attachment **bytes** are unchanged. At most 50 attachments / 100 MiB
are streamed into private copies, and no attachment is automatically scrubbed.
Adding any attachment marks `contains_private_context=true` and
`health_content=possible`, even when recorded-private-context sharing is off.
Recorded free-form private context also marks health content possible.

The ZIP, manifest and content digests are frozen at preparation. Previewed content
and the final ZIP are verified against these digests before exposure. Changing
selections invalidates the prepared artifact/review state. Search limits the event
viewer, not the bundle selection. Previews are capped at 128 KiB and disclose
truncation/nontext; the full original attachment remains in the ZIP. Large/binary
files should also be inspected with a trusted local viewer.

The ZIP is **not encrypted**. Review acknowledgement and explicit native save/share
are required. Public GitHub/Discord posts may expose the files to anyone; email
and other destinations retain/control their own copies. No secret scan can
promise an arbitrary user attachment is safe. Users may deliberately choose
sensitive files; the composer must not silently remove or rewrite them.

## Platform sections and instrumentation

| Surface | Apple | Android |
| --- | --- | --- |
| Viewer, selection, privacy, original attachments, ZIP review | iOS/iPadOS/macOS | Compose + Storage Access Framework |
| Native lifetime facts | UIKit become-active, SwiftUI active/inactive/background phase, AppKit active/resigned-active | Activity resumed/paused; not inferred process background |
| Nearby Connected Mac | Discovery, invitations/timeouts, transport changes, capabilities/destination, trace message counts and safe native errors | Unavailable: no Apple Multipeer topology |
| Direct CLI | iPhone connection/pairing, accepted capabilities, safe connection errors | Pairing/wait/connect/disconnect, accepted capabilities, reconnect errors |
| Scheduling | Queued requests, phone attempts/results, triggers and background expiration | Worker attempts/results/retries and scheduled result notification requests |
| Notifications | Native request/cancel/tap/rejection observations | Result request/cancel observations; request does not prove display |

Catalog availability is not a promise every platform emits every event. Missing
OS-specific hooks must not be fabricated. The older Android provider report
remains separate: it includes provider selections and export date/settings
context and must not be described as operational-only or anonymous.

Phone/Mac archives can be shared together as explicit attachments when the
connection is broken; v1 does not automatically transfer or merge them. Deferred:
automatic sensitive health-payload recording, subsystem-specific capture switches,
encrypted bundles, protocol-level cross-device correlation, richer platform
context and additional native notification/transport hooks.

## Verification

Native recorder/bundle tests exercise the shared privacy vector, no-consent disk
exclusion, independent sharing consent, bounded rotation, expiry, disable/restart,
clear, unknown fields, symlinks, original attachment bytes, failed cleanup and
frozen-artifact tampering. The root contract validator checks generation drift,
schemas, inventory checksums, declared producers/consumers and synthetic vectors.
Real-device connection/retry/notification and share-target behavior remain release
QA; a compile or synthetic vector is not evidence Seth's failure is diagnosed.
