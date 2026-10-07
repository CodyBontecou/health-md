# Diagnostics

Open **Settings → Diagnostics** to inspect local technical events and explicitly
prepare, review, save or share a ZIP. Operational recording is on at Debug by
default, bounded to seven days / 20 MiB. Disable it or clear stored diagnostics in
this screen. Info/Debug/Trace change verbosity, not health-data permission.

V1 private context is peer names only. Recording names requires a separate
15-minute opt-in; sharing recorded names is a separate, default-off choice.
Previously unrecorded details cannot be recovered. Private segments expire after
24 hours on the next app access. There is no automatic health-payload capture,
credential-store access, raw exception-text capture or diagnostic upload.

Filter events by time/subsystem/operation UUID and inspect their technical JSON.
Add any existing files using the Android document picker, including health
exports or screenshots. No new health reads are made. Selected streams are copied
unchanged, not scrubbed. Source names are included with a truncation flag for
unusually long names. All attachments and free-form private context are disclosed
as possibly containing health data even when recorded-name sharing is off.

**Prepare Bundle** freezes the snapshot and attachment copies. Inspect the
manifest, README, readable/JSON events and attachments; local previews are capped
at 128 KiB. Inspect large/binary originals with a trusted local viewer. Changed
selections invalidate preparation. A review acknowledgement enables explicit
**Share Reviewed ZIP** or **Save Reviewed ZIP** through native Android controls.
Only final reviewed ZIP copies are exposed by a narrow FileProvider, never the
recording directory. The app uses `noBackupFilesDir` for recordings/bundles.

ZIPs are **not encrypted** and operational-only is **not anonymous**. Public posts
can expose the files to anyone, and recipients control their copies. Clearing
also removes app-owned sharing cache copies, not original attachments or copies
saved elsewhere. Prepared reports expire after 24 hours on access; up to three
are retained, with storage separate from the event-segment budget.

Direct CLI connection/pairing/reconnect, worker results and scheduled result
notification requests are instrumented. Activity resumed/paused are explicit
native observations, not assertions about process suspension. A WorkManager
success is not a claim of complete health-data export, and a notification API
request is not proof of display. Apple Nearby Connected Mac is unavailable on
Android; the corresponding supported desktop destination is Direct CLI.

The older **provider report** remains separate. It includes provider selections,
export dates/settings and permission/error categories; it is not operational-only
or anonymous. It is never automatically added to these bundles.

See the [shared v1 contract](../../../../packages/contracts/diagnostics/v1/contract.md)
for schemas, privacy, limits and platform sections. Health export profiles,
Direct protocol bytes, CLI behavior and clinical/cloud boundaries are unchanged.
