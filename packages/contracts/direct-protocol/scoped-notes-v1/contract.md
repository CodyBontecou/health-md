# Direct scoped daily-note writes, version 1

Status: staged. The portable CLI conditionally negotiates version 1 after the source offers it,
then freezes policy/capture-bound receiver jobs, durable skip/install decisions and truthful receipts.
The native producers do not yet advertise this extension or attach its policies. Completing frozen
producer authority and cross-platform runtime qualification is required before native advertisement.

This independent extension applies the same personal-note settings to iPhone protocol v1 and
Android protocol v2 file exports. It changes neither historical daily export profiles nor pairing,
crypto, fingerprints, transfer frames, or existing manifest bytes when optional fields are absent.
The note is a personal document containing a scoped capture, not a complete health-data document.

## Negotiation and admission

Authenticated peer hellos may include `scopedDailyNoteVersions: [1]`. Both peers must explicitly
offer implemented version 1; absent, empty, or future-only lists mean unsupported. The source must
reject an unsupported note export before capture or sending manifests. The CLI must read the mobile
hello before adding this field to its reply: deployed Android peers reject unknown hello fields.
Both mobile platforms send their hello immediately after authentication. The CLI replies with
version 1 only when that source offered implemented version 1; absent, empty and future-only
source lists receive no extra hello field. Existing neutral export-history negotiation remains
unchanged. Native readers support the optional field but their current producers omit it.

The negotiated version is frozen in both durable jobs and must still be supported on resume.
Neither an unnegotiated policy nor a policy-less personal-note artifact in an extension job may be
silently interpreted using different merge semantics. Policy changes are manifest changes.

## Policy

The iPhone `DirectExportFileManifest` gains optional `scopedNotePolicy`; Android `ArtifactManifest`
gains optional `scoped_note_policy`. The inner object is identical, with required members:

| Member | Meaning |
|---|---|
| `version` | Integer 1 |
| `record_profile` | `apple-v8`, `apple-v11`, `android-frozen-v4`, `android-analytical-v5`, or `android-sleep-v6` |
| `owner_date` | Exact Gregorian `YYYY-MM-DD`, year 0001–9999 |
| `calendar_timezone` | Frozen named IANA calendar zone, including UTC/GMT aliases |
| `create_if_missing` | Whether the host may create a missing note |
| `inject_sections` | Whether generated Markdown sections may be updated |

Unknown policy members, unsupported versions/profiles, invalid dates/zones, null required fields,
and incorrect types reject. This policy is allowed only on a generated Markdown personal-note
artifact using `merge_markdown_preserving_preamble`. Its source platform, owner date and clock must
match accepted job authority. Its profile, date and clock must also match the actual strictly parsed
scoped capture. If sections are disabled, the patch contains no nonblank generated body.

The canonical [synthetic policy](fixtures/policy.json) is emitted by the Swift policy codec and
verified byte-for-byte by Kotlin and Rust. Existing v1/v2 fixtures stay unchanged.

## Destination and recovery requirements

Only the host knows whether the note exists. The source always stages a complete scoped patch,
including for existing-only settings; an empty mobile staging directory never justifies dropping it.
A missing note with creation disabled yields a durable skipped disposition without creating the
note or its parent directories. Scoped patches and merged notes are bounded to 8 MiB; larger
personal notes fail without replacement. Resume reuses that disposition, even if the owner later creates a
note. Skipped notes are absent from written-file counts and written-path lists. An existing note is
merged into a bounded private stage, preserving personal YAML, preamble and unrelated body bytes.

The receiver freezes skip or exact before/after digests and stage bytes before any destination
write. It never rerenders a ready plan after restart. Owner edits reject replacement. Existing
complete health-data/rollup documents are not personal notes and reject. Neither an upgrade nor a
downgrade may replay a plan with different merger authority: pre-scoped personal-note plans fail
closed; safe predecessor plans for other write modes retain their exact staged bytes.


## Receiver journals and receipts

The receiver freezes negotiated version 1 separately from the immutable manifests. New private
iPhone journal versions 6/7 (without/with history observations) and Android journal version 4
reject reinterpretation by earlier receivers. A missing, changed, future, or no-longer-negotiated
version rejects resume. An older job frozen without this extension retains its legacy semantics
when a newer connection offers version 1; negotiation never silently upgrades its manifests or
re-renders its stages. Skip IDs refer only to admitted existing-only note policies and are disjoint
from ready/committed install plans; invalid or orphaned dispositions reject before destination IO.

The durable JSON receipt adds `skipped_relative_paths` only when nonempty. Written-file counts and
`relative_paths` exclude skipped notes. The existing iPhone `total_bytes` remains the total verified
incoming artifact bytes, including skipped note patches; it is not a count of installed note bytes.
Date success counts continue to describe source processing rather than the number of note files
written. An all-skipped job may succeed with zero written files.

History sidecars contain only actually committed artifacts; skipped notes have no fabricated
committed hash. An all-skipped observed job retains its operation admission evidence with an empty
artifact list. The outer receipt carries skip paths separately. The MCP iPhone file presenter
returns at most 256 skip paths with the full count and a truncation flag, omitting the extension
when no note was skipped. These fields do not change the existing tool input schema.


The portable transport regressions use authenticated encrypted iPhone and Android peers through
`DirectClient::export_files` / `export_android`, including bounded binary transfer, final receipt
acknowledgement and completion. They prove host negotiation and dispatch without claiming native
app/device behavior. Pairing, query, wake enrollment/rotation, silence deadlines and neutral-history
regressions retain their original expectations with the mobile-first hello ordering.
