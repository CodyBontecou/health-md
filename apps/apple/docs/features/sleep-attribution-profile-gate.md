# Sleep attribution profile gate

Status: `planned` on Apple and Android. Target: **Issue #104 sleep-attribution-successor-profile-review**.

## User and consumer outcome

A daily export must have one stable owner-day meaning for the whole operation. Current Apple daily v8, Android frozen v4 and Android analytical v5 retain `night_begins`: the existing noon-to-noon window and its boundary clipping. No stored preference may change that meaning under the same public identity.

`morning_ends` assigns a whole session to its wake-up date without noon clipping. It changes meaning, even though the existing JSON/CSV/frontmatter shapes can represent the resulting values. It is therefore unavailable in current writers. The pickers disable new selection of this mode. Previously stored values remain visible and unchanged, with an unavailable explanation; captures reject them rather than substituting `night_begins` or exporting zeros.

The native proposed-mode calculations remain testable for future qualification. They are not production-profile approval. Apple v10, Android v6 and unified-v9 are **unapproved candidates**, not newly enabled writers. No daily version, signature fixture, API envelope or direct protocol is advanced by this gate.

## Operation and persistence authority

Apple's `AppleSleepCaptureContext` freezes timezone and attribution before suspension. `ExportOrchestrator` pins it around the whole operation; `HealthKitManager.fetchHealthData` respects the pin rather than shadowing it with each day's preference. API, connected, direct and report callbacks receive the same captured context. Task-local isolation prevents separate concurrent operations borrowing a pin.

New durable operations carry the context in `ExportSettingsSnapshot`. Pending scheduled/Shortcut requests also have a capture-only context, so legacy Shortcut configuration behavior need not freeze an engine/profile snapshot to retain sleep authority. New Shortcut runs pin before suspension and carry that pin into deferred work. Scheduling uses the saved request context without importing a portable profile's device preference. Only journal-store snapshot encoders opt into persisting `sleepCaptureContext`. Ordinary wire/portable snapshot encoders and canonical request fingerprints omit it, retaining their existing representation. This metadata is internal capture authority, not an export-profile discriminator. Portable setup does not import a device capture preference.

Recovery rules:

- A saved `night_begins` context remains authoritative even if today's preference is `morning_ends`.
- A saved `morning_ends` context stays unavailable even if today's preference is `night_begins`.
- A pending operation with no immutable attribution context cannot start additional capture. The application does not invent one from today's settings, rewrite the job, erase its journal or relabel existing items. The user may explicitly request a separate new operation.
- Existing captured spool/partition bytes and acknowledged frontiers are not recaptured or transcoded by this repair. Journal versions and existing fingerprint/engine/protocol authorities are unchanged.
- Historical records whose `ExportTimeContext.sleepDayAttribution` is absent retain their historical meaning. An absent field in a *pending operation snapshot* is not evidence that its mutable draft-era preference was pinned.

Android resolves one explicit context across chunks. Its current repository and writer contexts reject `morning_ends` before physical capture/render/upload. Stored preferences are not migrated. The native sleep reducer's proposed-mode tests remain qualification controls; shipped writer controls use the historical rule and include unavailable-context negatives.

## Required enabling change

The target above must include all of the following before the mode becomes available:

1. Explicit owner approval of successor public profiles with owner-day, clipping, timezone and exported attribution metadata. Do not invent version approval or reuse Apple v8/Android v4-v5.
2. Reader adoption and mixed-version tests for Apple, Android, shared Rust core, CLI, website, API/direct/connected receivers and the external Obsidian plugin.
3. Approved durable-job profile/context selection, downgrade/resume behavior and migration/rollback rules. Portable configuration remains a separate contract.
4. Synthetic overnight and noon-spanning fixtures through every format and surface, both preference-mutation directions, separate concurrent operations and partial recovery.
5. Native accessibility metadata checks on phone/tablet and VoiceOver traversal with hints enabled. Local model/helper tests are not spoken/device qualification.

Historical signature fixtures must remain byte-identical. Capability/registry projections must be updated by their canonical owner/generator, not by editing generated native output or repinning a historical registry.
