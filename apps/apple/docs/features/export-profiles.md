# Export Profiles

## Status

- **Docs status:** draft (implementation in progress; not yet user-visible)
- **Video priority:** medium
- **Primary screen:** Export (profile picker, planned), Schedule (per-profile entries, planned)
- **Source files:** `HealthMd/Shared/Models/ExportProfile.swift`, `HealthMd/Shared/Models/ExportSettingsSnapshot.swift`, `HealthMd/Shared/Models/AdvancedExportSettings.swift`, `HealthMd/Shared/Models/ExportSchedule.swift`

## What it does

Export Profiles are saved, named export configurations — like custom presets in other tools. Each profile freezes a complete set of output-affecting settings (metric selection, formats, write mode, filename/folder templates, roll-ups, lossless capture, Daily Note settings) together with an export destination, so one profile can be "daily everything, JSON, vault folder A" and another can be "weekly sleep-only, Markdown + weekly roll-up, vault folder B."

Profiles solve two real limitations of the single-settings model:

1. **Concurrent, different automations.** Today one schedule, one destination, one settings blob exist. With profiles, a daily profile can keep writing to the existing vault while a weekly profile lands the prior week (including weekends — a trailing date range, not an ISO-week roll-up) in a different location.
2. **Quick scoped exports.** "Just sleep" or "just workouts" becomes one tap on a saved profile instead of toggling metric selection back and forth.

## Platform-neutral contract

- A profile is a name plus an immutable `ExportSettingsSnapshot` and an `ExportTargetSelection` binding. The snapshot is the same representation already sent to Mac export jobs and frozen into `PendingExportRequest`, so durable resume, renderer pinning, and peer compatibility reuse existing machinery unchanged.
- Profiles choose **which request** produces files. They never change the public export schema: identical profile settings produce byte-for-byte identical `healthmd.health_data` output for the platform's output profile. `HealthMdExportSchema.version` does not move for profile work.
- HealthKit authorization, quota/account state, schedules, and device timezone are excluded from profile payloads.
- External references (Shortcuts, CLI, automation broadcasts) resolve profiles **by stable UUID**, with the display name accepted as a convenience alias. Unresolvable references fail with a typed error and never silently fall back to live settings.

This capability is recorded as `export.profiles` in `packages/contracts/product-capabilities.json` (classification `planned` on both platforms). Note the deliberate distinction from the manifest's `output_profiles`, which name shipped data-schema profiles (`apple-v8`, `android-frozen-v4`, …); user export profiles are not schema profiles.

## Decisions

Recorded product decisions for phases 2–5:

1. **Editing authority:** once any profile exists, the Export tab edits the **active profile exclusively**. Live `AdvancedExportSettings` is the source of truth only in legacy mode; legacy keys are not dual-written and go dormant after migration.
2. **Last profile:** deleting the final profile is **forbidden** (implemented in `ExportProfileStore.delete`).
3. **Destinations:** Phase 2 ships a **multi-vault store** — each profile can bind its own security-scoped folder bookmark (and API endpoint), not just a subfolder under one root.
4. **Free-tier quota:** unchanged — **10 total free export actions**, consumed per exporting request regardless of profile, schedule, or source. No per-schedule cap is added; the schedule UI should surface projected monthly usage so the burn rate is visible.
5. **Scheduled entries:** maximum **100 scheduled profile entries** (single constant; revisit toward ~20 before ship if recovery UX or pending-request volume becomes hostile). All entries are evaluated by **one coalesced wake-up worker** — custom "every N days/weeks/months" cadences already register as daily wake-ups that locally reject off-cadence fires, so N entries cost one BGTaskScheduler identifier, not N.
6. **Concurrent runs:** profile runs that fire at the same moment execute **concurrently**. In-flight identity is per profile, so a daily and a weekly profile never deduplicate each other, and a profile schedule can run while a manual export is in flight. Residual risk to verify in Phase 3: memory during concurrent lossless capture, and serialization at a single Connected Mac peer (peer-bound durable sessions may still queue at the peer).
7. **Today Refresh:** **per schedule entry**, refreshing that entry's profile's today snapshot on its own interval. A global refresh tied to whichever profile happens to be active would surprise users when the active profile changes.
8. **Worker APNs metadata:** `syncSchedule` sends a **bounded list of fire-time metadata only** (enabled state, cadence, preferred time, timezone) for each entry — no profile names, no health data, and recovery notifications remain local per the existing server-visible-notification decision.
9. **Zero-parameter intents:** "Export Yesterday's Health Data" and friends resolve the **active profile** once profiles exist. This is a versioned behavior change for previously saved Shortcuts: called out in release notes and the website Shortcuts docs, with the profile parameter available for explicit pinning.
10. **Direct protocol additivity:** structurally additive — v1 request models ignore unknown fields (no `deny_unknown_fields`) and the new `profileReference` is optional on the new side. The new `settingsPolicy: "profile"` enum value **fails closed on old peers**: an old decoder rejects the unknown variant with a typed invalid-request error rather than misinterpreting it. Phase 5 must still add same-version Swift↔Rust round-trip fixtures plus old-CLI/new-phone and new-CLI/old-phone combination tests before this is claimed proven.
11. **Profile discovery on CLI:** a dedicated `healthmd profiles list` subcommand (fresh direct query). The status payload stays readiness-only; an MCP listing tool is deferred.
12. **Naming:** **profiles** (`export.profiles`), as shipped.
13. **Shared roll-up files:** two profiles writing the same roll-up file in Update mode is **allowed**; Update-mode section merging and persisted append/merge replay plans already make repeated writes idempotent.

## Persistence and migration

- `ExportProfileStore` persists the ordered list plus `activeProfileID` to UserDefaults as one JSON payload, following the `ExportSchedule` pattern. An empty list means **legacy mode**: the app keeps reading live `AdvancedExportSettings` exactly as before. Undecodable data degrades to legacy mode rather than changing export behavior.
- First-run migration synthesizes a localized "Default" profile from current live settings and the saved export target. It runs at most once (no-op when any profile exists), and legacy `AdvancedExportSettings` keys are never deleted.
- Deleting every profile returns the app to legacy mode.

## Store semantics

- Names are trimmed and unique (case-insensitive) with automatic " 2", " 3" suffixes; lookups by name are trimmed and case-insensitive.
- Mutations (`add`, `rename`, `updateSettings`, `updateTarget`, `duplicate`, `delete`, `activate`) persist immediately and touch `updatedAt` where meaningful.
- Deleting the active profile activates the first remaining profile. **Deleting the last remaining profile is forbidden** — once profiles exist, at least one must remain so exports always resolve a concrete configuration.
- A dangling persisted `activeProfileID` resolves to nil rather than crashing.

## Phasing

1. Model + store + migration + tests (this change).
2. Manual Export profile picker; `ExportPreviewView` binds to the selected profile's snapshot; multi-bookmark destination store.
3. Per-profile scheduled entries: `ScheduledExportEntry` list bounded to a fixed maximum, reusing `ScheduleDateMath` per entry; `PendingExportRequest` gains optional profile identity; notifications/history label the profile.
4. Shortcuts/App Intents `profile` parameter (UUID-pinned, name alias); Android `AutomationReceiver` profile extra.
5. Direct protocol profile reference (`settingsPolicy: "profile"` + `profileReference`) resolved on iPhone by UUID, `profile_not_found` typed failure, CLI `--profile`, MCP parameter, fixtures.
6. Android parity (repository, per-profile WorkManager, UI).

Quota accounting is unchanged: every exporting request still consumes one free export action regardless of which profile produced it. The schedule UI must surface projected monthly usage across all enabled entries (decision 4).

## Testing

- `HealthMdTests/Models/ExportProfileStoreTests.swift` covers legacy mode, corrupted-data fallback, dangling active ids, migration idempotency, persistence round trips, Codable round trips, CRUD semantics, name normalization/uniqueness, and clock-injected timestamps.
- Phase 2+ gates: snapshot-equality (identical profile ⇒ identical output) via existing byte-for-byte fixture comparisons, `ScheduleDateMath` reuse per scheduled entry, protocol round-trip fixtures for the profile reference, and the full consumer gates named in the repository root `AGENTS.md`.

## Limitations

- Per-profile destination bookmarks and API endpoint configs land with the multi-vault store in phase 2/3. The model carries the target enum from day one, and the multi-vault decision is recorded above.
- Profile payloads are device-local and are not iCloud-synced (destination bindings do not transfer usefully across devices).
- Roll-up behavior is per-profile settings; it does not retroactively regenerate historical roll-up files.
