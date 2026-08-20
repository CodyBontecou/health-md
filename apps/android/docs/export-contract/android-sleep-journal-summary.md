# Android sleep journal summary

**Status:** compatibility conformance rule

**Rule IDs:** `noon-to-noon-sleep-window-v1` (default), `wake-date-sleep-window-v1` (optional setting)

**Scope:** Health Connect compatibility summaries and detailed sleep records

## Journal-day ownership

Android uses the same established sleep-summary day as Apple: the exported journal date owns the
half-open local interval from noon on that date to noon on the following date. A session ending
exactly at the opening noon belongs only to the preceding journal day; a session starting at that
noon belongs to the new day.

## Wake-up-date attribution (issue #104)

The shared **Sleep Day Attribution** setting (`settings.sleep-attribution`) selects which journal
day owns a sleep session:

- **Night begins** (`night_begins`, default, rule `noon-to-noon-sleep-window-v1`): the shipped
  behavior described throughout this document. Existing exports never change silently.
- **Morning ends** (`morning_ends`, rule `wake-date-sleep-window-v1`): the journal date owns every
  source session whose **end** falls on that date, matching the Health Connect UI. Owned sessions
  are kept whole — never clipped at a noon boundary and never split between two journal days —
  and afternoon naps stay on the day they end. Malformed zero/negative-length records land on
  their end date instead of the start-date noon fallback.

The setting is a device-local capture preference (DataStore key `sleep_day_attribution`) snapshotted
with the operation timezone at the entry to every Health Connect capture: manual, scheduled, API,
direct file, report, fallback, and widget reads. An explicit override distinguishes a real
`night_begins` choice from “read the stored preference,” so fallback capture cannot silently replace
a pinned `morning_ends` result with default-mode data. Apple persists the identical raw values and
default (`healthKit.sleepDayAttribution`, UserDefaults). The setting is deliberately excluded from
portable Share My Setup envelopes and durable retry snapshots on both platforms, and it changes
only owner-date assignment — never values, units, reducers, stage identities, or the frozen v4 /
analytical v5 export shapes. Cloud provider sidecars keep their provider-native attribution; the
setting governs the primary Health Connect read path.

The read interval in the next section is unchanged for both modes: its prior-day noon start
already covers overnight sessions ending on the first requested date because Health Connect
interval reads are overlap-based.

One `ZoneId` is captured when an operation starts. Its local noons, midnights and record display
values remain stable for the whole operation, including across daylight-saving transitions. Source
instants and source-provided offsets are retained separately and are not replaced with the export
zone.

Health Connect sleep reads use a sleep-only interval. For requested dates `first...last`, the read
starts at noon on `first - 1 day` and ends at noon on `last + 1 day`. The prior-day lookback protects
the first journal day from start-filtering provider implementations; following-noon coverage
captures the last requested night's wake. Ordinary health metrics retain their midnight windows.

## Frozen summary aggregation

The v4 and v5 Android compatibility profiles retain their shipped additive sleep aggregation in
both attribution modes:

1. Ignore zero-length and negative sessions for summary purposes.
2. Clip each valid candidate interval to the journal window in night-begins mode; in morning-ends
   mode the owned session is the unit and is never clipped. The source record itself remains
   unclipped in both modes.
3. Add the elapsed duration of every owned session to total and in-bed time. Existing Android
   profiles do not de-duplicate overlapping provider sessions or select a principal cluster.
4. Set bedtime to the earliest owned session start and wake to the latest owned session end.
5. Clip stages to their parent session (and the journal window in night-begins mode), then add
   every recognized stage interval to its corresponding summary bucket. Overlapping provider
   stages remain additive.

Keeping this behavior is intentional. Selecting a principal session, applying a continuity
threshold or resolving conflicting providers would change the meaning and aggregation of shipped
summary fields. Such behavior requires a new public Android schema profile rather than a silent
change to frozen v4/v5 output.

The issue 96 correction is therefore limited to the query and ownership defect: the full overnight
session is now available in the date's noon-to-noon projection, so a nested `23:08–23:48` fragment
cannot hide the enclosing `22:00–05:30` bedtime and wake boundaries.

## Detailed and raw fidelity

All source sleep sessions associated with the journal window remain in granular output, including
malformed sessions excluded from explicit duration and session-boundary calculations. Granular
session and stage rows preserve their original source instants, nanoseconds, identities and nullable
source offsets. Local clock fields are projections in the operation's captured export zone.

Canonical raw Health Connect records continue to use their independent raw-record ownership and
fidelity contract. Consumers reconstructing source events must use raw/detailed records rather than
inferring them from the compatibility headline.

## Schema decision

This change conforms Android to the already-documented noon-to-noon sleep ownership contract while
preserving the aggregation meaning of the frozen `ios-v4` and shipped `android-analytical-v5`
profiles. It changes no public key, JSON type, unit, label, aggregation rule or frontmatter key, so
those profile versions and signature fixtures do not change. The wake-up-date mode is a new,
explicitly versioned window rule (`wake-date-sleep-window-v1`) selected by an opt-in user setting;
the default mode retains the shipped noon-to-noon boundary and clipping behavior for existing
installs; it does not promise that an arbitrarily long session crossing noon remains whole.

A principal-session rule, overlap de-duplication, continuity threshold, stage-authority rule or
other public semantic change must use a new explicit profile/version under the existing guardrail.

## Verification and device QA

Pure JVM tests cover the issue reproduction, first-day lookback, additive overlapping sessions,
empty and stage-less records, exact-noon ownership, invalid intervals, spring/fall DST, differing
source offsets, deterministic ordering, single/range parity, and — for both attribution modes —
late-night midnight-spanning sessions (23:45–07:30), single-day naps, two consecutive nights
without duplication, additive overlap, and malformed-session day placement. Existing
Markdown/Bases, JSON, CSV and schema-signature contract tests remain the exporter gate.

Physical Health Connect QA remains a release smoke test: on the Pixel 7, import or sync an overnight
session plus a nested short fragment, export the owning journal date as both one day and a range,
and compare the headline and detailed records. Device QA is not required by the deterministic JVM
suite.
