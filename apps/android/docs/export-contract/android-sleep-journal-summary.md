# Android sleep journal summary

**Status:** shipped compatibility rule; alternate ownership is `planned`

**Shipped rule ID:** `noon-to-noon-sleep-window-v1`

**Proposed calculation rule:** `wake-date-sleep-window-v1` (unavailable in production profiles)

**Scope:** Health Connect compatibility summaries and detailed sleep records

## Journal-day ownership

The exported journal date owns the half-open local interval from noon on that date to noon on the following date. A session ending exactly at opening noon belongs only to the preceding journal day; one starting at that noon belongs to the new day. This is `night_begins`, the shipped default on Apple and Android.

One `ZoneId` is captured when an operation starts. Its noons, midnights and display values remain stable across chunks and daylight-saving transitions. Original source instants and nullable source offsets remain separate.

Health Connect sleep reads use a sleep-only interval. For requested dates `first...last`, the read starts at noon on `first - 1 day` and ends at noon on `last + 1 day`. The prior-day lookback protects the first journal day from start-filtering provider implementations; following-noon coverage captures the last requested night's wake. Ordinary health metrics retain their midnight windows.

## Sleep Day Attribution gate (issue #104)

`settings.sleep-attribution` is **planned** on both platforms. The exact target is **Issue #104 sleep-attribution-successor-profile-review**, documented in `apps/apple/docs/features/sleep-attribution-profile-gate.md`.

`morning_ends` would assign a whole source session to the calendar date of its end, without noon clipping. That changes public meaning and cannot ship under immutable Apple v8 or Android v4/v5 identities. The repository and current writer contexts reject this mode before provider reads or output. The settings control disables new selection; stored values remain unchanged and unavailable, rather than being coerced to `night_begins`. A changed preference applies only to a separately requested new operation, never to a saved explicit capture context.

Apple v10, Android v6 and unified-v9 are unapproved candidates. Enabling alternate attribution requires profile approval, exported metadata, consumer adoption and durable-context qualification. It is not authorized by an internal window-rule constant or a unchanged structural signature.

The same device-local raw values remain in DataStore (`sleep_day_attribution`) and Apple UserDefaults (`healthKit.sleepDayAttribution`). Portable Share My Setup does not import them. Apple internal durable journals now retain their operation context separately from portable/wire encoding; missing or unapproved recovery contexts remain unavailable without journal erasure. Android passes one explicit context across capture chunks and does not substitute provider-native single-day semantics after an empty authoritative range.

## Frozen summary aggregation

Android frozen v4 and analytical v5 retain these rules:

1. Ignore zero-length and negative sessions for summary purposes.
2. Clip each valid interval to the shipped noon-to-noon journal window. The source record itself stays unclipped.
3. Add elapsed duration of every owned session to total and in-bed time. Existing profiles do not de-duplicate overlapping provider sessions or select a principal cluster.
4. Bedtime is the earliest owned session start; wake is the latest owned session end.
5. Clip stages to their parent session and journal window, then add each recognized interval to its bucket. Overlapping provider stages remain additive.

The issue 96 correction remains limited to the query/ownership defect: the full overnight session is available in its noon-to-noon projection, so a nested `23:08–23:48` fragment cannot hide enclosing `22:00–05:30` boundaries.

Principal-session selection, overlap de-duplication, continuity thresholds, stage-authority changes and alternate owner-day/clipping semantics all require reviewed new public profiles.

## Proposed calculation and source fidelity

Native qualification tests retain the wake-date calculation: owned sessions remain whole; afternoon naps stay on their end date; malformed records use their end date for detailed placement. Those calculations are not available to current immutable writers.

Granular rows preserve original instants, nanoseconds, identities and nullable source offsets. Canonical raw Health Connect records retain their independent ownership/fidelity contract. Consumers must not reconstruct source events from the compatibility headline.

## Compatibility and verification

No shipped profile version or signature fixture changes. Existing historical expectations and bytes remain authoritative. JVM controls cover noon ownership, overnight/noon-spanning sessions, additive overlap, malformed/stage-less records, DST, source offsets and proposed calculations. Production repository, file, API, direct and preview controls also reject unapproved contexts without reads/output and retain pinned night-begins ownership after preference edits.

Native/device and external-consumer validation remain separate release gates. Local JVM/helper tests do not qualify physical Health Connect, VoiceOver or successor profiles.
