# Direct scoped daily-note writes, version 1

Status: staged. Models and capture-binding semantics are implemented. The mobile producers and
portable receiver do not yet advertise or execute this extension. The host preparation API
validates policy-bound patches and returns a ready stage or an explicit missing-note skip;
policy-bearing manifests in the receiving pipelines currently fail closed. Completing destination skip recovery, frozen producer authority, and
cross-platform runtime qualification is required before advertising version 1.

This independent extension applies the same personal-note settings to iPhone protocol v1 and
Android protocol v2 file exports. It changes neither historical daily export profiles nor pairing,
crypto, fingerprints, transfer frames, or existing manifest bytes when optional fields are absent.
The note is a personal document containing a scoped capture, not a complete health-data document.

## Negotiation and admission

Authenticated peer hellos may include `scopedDailyNoteVersions: [1]`. Both peers must explicitly
offer implemented version 1; absent, empty, or future-only lists mean unsupported. The source must
reject an unsupported note export before capture or sending manifests. The CLI must read the mobile
hello before adding this field to its reply: deployed Android peers reject unknown hello fields.
Both mobile platforms send their hello immediately after authentication. New mobile readers omit
nil capabilities and accept the corresponding optional field; no implementation advertises it yet.

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
