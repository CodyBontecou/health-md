# Versioned sleep day attribution

Status: owner-authorized implementation, not yet production-qualified. On 2026-10-05 the owner requested the compatibility work needed to make Morning ends functional after the shipped-profile gate was explained. This authorizes the successor implementation below, not a product release, deployment, real-device export/upload, or adoption of the unrelated unified-v9 proposal.

## Shared outcome

A user can choose which daily export owns a sleep session. A capture operation resolves one calendar timezone, attribution and public profile before suspension and retains that authority through every day, destination, retry and recovery. Native capture remains responsible for HealthKit/Health Connect semantics. This contract changes only summary/session owner-day and clipping; it does not change canonical source ownership, stage equivalence, source provenance, native overlap/precedence rules, units or unrelated metrics.

## Profile identities

| Source | Public profile | Daily version | Attribution |
| --- | --- | --- | --- |
| Apple | `apple-v8` | 8 | historical `night_begins` |
| Android | `android-frozen-v4` | 4 | historical `night_begins` |
| Android | `android-analytical-v5` | 5 | historical `night_begins` |
| Apple | `apple-v11` | 11 | `morning_ends` |
| Android | `android-sleep-v6` | 6 | `morning_ends` |

Apple v5/v6/v7 remain readable historical Night begins documents. Apple v8 and Android v4/v5 writers, signatures, fixtures and already captured bytes remain immutable. Night begins remains the default and selects its existing native profile. New Morning ends operations select the explicitly versioned successor, not a relabeled old writer. The Apple and Android successor grammars remain native profiles; their different payloads do not claim a unified daily grammar merely because they share an attribution rule. Unified daily v9 remains a separate proposal.

The 2026-10-08 allocation audit reserves Apple daily v11 for sleep ownership because the separate WHOOP/cloud workstream already defines daily v10 and `apple_health_data_v10` for Night begins plus WHOOP provider-v2 cycle steps. Draft sleep v10 contexts and artifacts do not become approved v11 inputs; their bytes/markers remain intact and unavailable. The retired synthetic v10 fixture is rejection evidence, not a supported writer profile. This reallocation changes no shipped schema, default, raw archive or protocol.

## Owner-day and clipping

### Night begins — historical profiles

The owner date labels its half-open local noon-to-following-noon window. Summary intervals and stage-duration calculations are clipped to that window under the platform's existing reducer. A session ending at opening noon is not owned by the new window; a session starting there is. Previously shipped additive/deduplication and stage handling remain unchanged.

Historical detailed payloads have independently versioned platform behavior. Apple v8 granular `sleepStages` intervals are clipped to the journal window and retain the sample metadata. Android v4/v5 detailed stages and native parent records retain original source intervals even when the summary counts only their overlap with the window. A 10:00–13:00 source interval contributes one hour to the note whose window opens at 12:00: Apple's granular projection starts at 12:00, while Android's source detail still starts at 10:00. Neither historical profile promises whole-session summary ownership. Canonical source archives keep their separate fidelity contract; consumers must not infer source intervals from a historical summary or equate these granular projections.

### Morning ends — successor profiles

The owner is the calendar date of the source session's end instant in the captured IANA timezone. A wake exactly at local midnight belongs to the new date. In a requested owner-date interval `[first, last]`, end instants must fall in `[midnight(first), midnight(last + 1 day))`.

Owned valid sessions retain their complete source start and end, including sessions beginning before the requested date or spanning noon. Summary duration uses elapsed instants, not subtraction of wall clocks. Stages retain the existing platform interpretation and are clipped only to their parent session, never to a noon or midnight summary window. Malformed/zero-length sessions do not create fabricated summary duration; existing detailed-source fidelity remains independent.

Afternoon naps belong to their end date. Source offsets, nanoseconds, identities and canonical raw-record ownership remain unchanged. Apple Core and Android Light do not become equivalent through this feature; readers must retain the native identities.

## Exported authority

Self-describing daily documents declare their native version and profile. A successor JSON record has `schema: healthmd.health_data`, `schema_version: 11` or `6`, and `schema_profile: apple-v11` or `android-sleep-v6`. Native Android analytical aliases, where retained, must agree with the canonical identity and cannot identify the output as v4/v5.

Its `time_context` contains:

```json
{
  "calendar_timezone": "America/Los_Angeles",
  "timestamp_timezone": "UTC",
  "sleep_day_attribution": "morning_ends",
  "sleep_owner_day_rule": "session_end_date",
  "sleep_interval_clipping": "none"
}
```

The calendar timezone is the frozen owner-date authority. Apple and canonical API timestamps remain UTC. Where a native Android local format retains its existing timezone-less calendar clock representation, `timestamp_timezone` must truthfully declare the captured calendar timezone rather than claim UTC; exact source timestamp representations remain independently authoritative. The shared attribution meaning is identical in either representation.

Native successor JSON preserves admitted numeric sample precision independently of daily summary availability. Apple v11 heart-rate/SDNN and blood-oxygen, blood-glucose and respiratory-rate samples retain their captured UTC fractional timestamps, values and metadata even when no daily summary exists. Android v6 heart-rate samples retain the admitted numeric value, UTC fractional timestamp and independently authoritative exact instant/identity. Apple SDNN and Android RMSSD remain different metrics. These detail projections do not authorize absent summaries or establish complete source archives; The draft four-format adapters now carry these five sample families through frozen selection authority, preserving complete native objects in CSV/Bases and the declared timestamp/value/unit projection in Markdown. Broader native/core detail and production-route qualification remain required. Shipped Apple v8 and Android v4/v5 projection bytes remain unchanged.

The three sleep fields are a single atomic authority: missing, unknown or contradictory values are rejected, not defaulted. A successor needs a valid calendar timezone and a timestamp timezone of UTC or the declared calendar timezone. Apple v11 requires UTC machine timestamps. Existing versions cannot opt into Morning ends merely by adding a field.

CSV retains its existing column/header contract and emits `Metadata` rows for `schema`, `schema_version`, `schema_profile`, `time_context.calendar_timezone`, `time_context.timestamp_timezone`, and the three `time_context.sleep_*` fields. Markdown/Bases use the equivalent frontmatter when enabled. Metadata-off Markdown must still visibly identify the successor profile, timezone and wake-date/whole-session meaning without reintroducing frontmatter or optional health metadata; updated readers must recognize that explicit attribution declaration. It must not masquerade as an ordinary unversioned Night begins note.

Custom/placeholder frontmatter cannot override successor schema/profile/time-context authority. Attribution is independent of metric selection, empty sleep and archive completeness; a day with no sleep is not permission to drop its operation's mode.

## API, direct and connected consumers

Existing API envelopes remain independently versioned. Each envelope must declare the actual native daily schema/profile and contain matching records; it cannot retain `daily_record_schema_version: 8`/`4` around successor records. Batch partitions retain one captured profile and timezone, including failure-only batches. Native Android's existing API normalization remains distinct from local analytical presentation, with explicit profile authority and truthful native stage identities.

Raw/extract readers preserve the source daily version and time context in records, projections and receipts. Generated-file receivers transfer the actual production artifacts, not locally reconstructed approximations. Request fingerprints and the negotiated direct-protocol transcript are not changed by a public daily schema addition.

Connected peers must explicitly advertise successor support before a new Morning ends job can capture/transfer data for peer-side rendering. A missing capability means unsupported, never permission to let an older Mac discard attribution and write v8. Already captured artifact bytes remain opaque and authoritative during recovery.

Range/period output cannot call Morning ends data Apple v8 source data or rules v8. Historical calendar v8 and range v9 outputs remain immutable. Successor Apple roll-ups require a separate `healthmd.rollup_summary` v11 profile identifying Apple v11 source/rules and exported attribution; existing independent range v9 is not rewritten. Clinician reports must label the captured attribution without altering their source archive meaning.

## Durable authority and migration

New internal contexts persist the approved native profile/attribution revision alongside timezone and mode. Ordinary portable setup still excludes the device-local preference and capture authority. Resume never reads the current preference to reconstruct a missing historical promise.

- Existing Night begins contexts with no successor discriminator retain their historical profile.
- Draft-era Morning ends contexts or records with no approved successor discriminator remain unavailable for new capture/rendering, even after the setting is enabled.
- New Morning ends contexts remain Morning ends after a preference change to Night begins, and the reverse holds for saved Night begins contexts.
- Recovery commits existing immutable spool/partition bytes before considering fresh capture availability. It never recaptures, transcodes, retags or erases them.
- A version/profile incompatibility or missing capture authority fails closed with a bounded health-free error while retaining the job. A downgrade cannot reinterpret an unrecognized successor as a legacy default.
- New profile-aware registry inventory is independently versioned. Do not repin the historical v1 registry or change old renderer revisions merely to add profiles. Successor registry v2 contains only `apple_health_data_v11` and `android_sleep_v6`; old profiles continue to request v1 explicitly. In v2 Android `sleep_light` and Apple `sleep_core` are `platform_distinct` native identities with the counterpart reported unavailable, not a Core/Light alias. Android v6 emits `sleep_light_hours`, never `sleep_core_hours`. Historical v1 mappings and outputs remain unchanged.
- Append/merge behavior must not silently combine conflicting ownership under a single old schema identity. Explicit new exports may replace user-selected outputs; migration is never an automatic historical rewrite.

## Internal handoff versioning

Successor-only [semantic input/canonical model v2](../../semantic-input/v2/contract.md) and [render input/artifact plan v2](../../render-input/v2/contract.md) carry explicit captured authority and a closed successor profile set. Historical v1 schemas, result bytes and default build-info pins remain unchanged. New callers choose version 2 explicitly alongside registry v2; changing a mode must never widen or repin historical v1 promises.

## Verification required before enabling

The accepted test seams are the existing production exporters/artifact planners, API envelopes and real readers, durable export operations, native capture adapters with synthetic SDK inputs, and the public native controls. Enum/helper success alone is insufficient.

Qualification requires independently expected synthetic overnight, noon-spanning, midnight-boundary, DST, nap and invalid-session cases; all supported formats and metadata settings; empty sleep; mixed historical/successor reads; both preference-mutation directions; concurrency; partial recovery/downgrade; configuration protection; phone/tablet accessibility metadata and spoken VoiceOver evidence. Run affected Apple, Android, core, contracts, CLI, website/API and pinned external Obsidian checks, and keep health-data QA artifacts private and ignored. Update capability/registry projections through their canonical owner/generator only after implementation evidence supports the classification.

No successor writer is qualified until the completion audit maps every obligation above to inspected artifacts and real verification results. No product release or health-data upload is implied by owner authorization of the implementation.
