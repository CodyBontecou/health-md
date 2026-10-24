# Diagnostics

Open **Settings → Diagnostics** on iPhone/iPad or macOS. Technical event IDs,
native error domains/codes, timing, connection state, and source locations are
available locally. Info/Debug/Trace change verbosity, not health-data permission.
Operational recording is on at Debug by default; disable it or clear stored
reports in this screen. Records are bounded to seven days / 20 MiB.

Peer names require a separate **Record Private Context for 15 Minutes** action.
Previously unrecorded details cannot be recovered. Including already-recorded
private context in a report is a separate, default-off selection. Private
segments expire after 24 hours on the next app access. V1 never automatically
captures health payloads, pairing codes, credential stores, or arbitrary error
text.

Choose the event time range/subsystem/operation UUID, inspect events, and add
any existing files you want, including health exports or screenshots. Attachment
bytes are copied unchanged and are not scrubbed; source names are included
(with disclosed truncation for unusually long names). No new health reads are
performed. Attachments or free-form private context mark the bundle as possibly
containing health data regardless of the private-context sharing switch.

**Prepare Bundle** freezes the selected events and attachment copies. Open the
manifest, README, event JSON/text and attachments to review them. Previews are
limited to 128 KiB; inspect large/binary originals with a trusted local viewer.
Changing selections invalidates the prepared artifact. A review acknowledgement
and an explicit confirmation are required to open the native share sheet/picker.
On iPhone/iPad, use **Save to Files** in the native share sheet to inspect the ZIP
outside the app before sending it. macOS also has **Save Reviewed ZIP…**, using the
native save panel with an unencrypted-file disclosure.

The ZIP is **not encrypted** and operational-only is **not anonymous**. Public
posts can expose the report to anyone; recipients control their own copies.
Health.md does not upload diagnostics automatically and cannot recall saved or
shared copies. Clearing removes app-owned diagnostics, not original attachments.
Prepared bundles expire after 24 hours on next access; up to three are retained.
Their storage is separate from the 20 MiB event-segment limit.

For a Connected Mac problem, record on both devices, reproduce the failure, and
prepare a report on each. When the connection is broken, manually share both
ZIPs or attach one to the other; there is no dependency on a working connection.
Discovery/invitation/timeouts, capabilities/destination readiness, scheduling and
notification requests are the first instrumented surfaces. A notification request
is not proof it appeared, and a Mac resigning active is not proof it suspended.

The [shared v1 contract](../../../../packages/contracts/diagnostics/v1/contract.md)
defines privacy, limits, missingness, fixtures, and platform-specific observations.
Health export schemas and Direct protocol bytes are unchanged.
