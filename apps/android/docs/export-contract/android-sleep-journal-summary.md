# Android sleep journal summary

**Status:** compatibility conformance rule

**Rule ID:** `principal-overnight-sleep-v1`

**Scope:** Health Connect compatibility summaries and detailed sleep records

## Journal-day ownership

Android uses the same established sleep-summary day as Apple: the exported journal date owns the
half-open local interval from noon on that date to noon on the following date. A session ending
exactly at the opening noon belongs only to the preceding journal day; a session starting at that
noon belongs to the new day.

One `ZoneId` is captured when an operation starts. Its local noons, midnights and record display
values remain stable for the whole operation, including across daylight-saving transitions. Source
instants and source-provided offsets are retained separately and are not replaced with the export
zone.

Health Connect sleep reads use a sleep-only interval. For requested dates `first...last`, the read
starts at noon on `first - 1 day` and ends at noon on `last + 1 day`. The prior-day lookback protects
the first journal day from start-filtering provider implementations; following-noon coverage
captures the last requested night's wake. Ordinary health metrics retain their midnight windows.

## Principal overnight rule

The compatibility headline is selected by the named `principal-overnight-sleep-v1` rule:

1. Ignore zero/negative sessions and sessions longer than 24 elapsed hours for summary purposes.
2. Clip valid candidate coverage to the journal window. The source record itself remains unclipped.
3. Put overlapping sessions, contiguous sessions, and split sessions separated by no more than 90
   elapsed minutes into one cluster.
4. Select the cluster with the greatest de-duplicated coverage.
5. If coverage is tied, prefer a cluster spanning the journal night's local midnight, then break
   remaining ties by stable start/end/source ordering.
6. Set bedtime and wake to the selected cluster's first and last covered instants. Compute total and
   in-bed time from the union of its session intervals, so overlaps and duplicate fragments count
   once and split-sleep gaps do not count.
7. Resolve stage summaries on a non-overlapping timeline. The longer parent session is authoritative
   where a short duplicate fragment conflicts; stable source and explicit stage precedence break
   exact ties. Granular stages are not rewritten to match the summary.

A shorter disconnected daytime nap therefore remains available as detail but cannot pull the
headline earlier or later. Likewise, a tiny midnight-crossing fragment cannot outrank a
substantially longer disconnected sleep period. Stage-less sessions can still be the principal
period.

## Detailed and raw fidelity

All source sleep sessions associated with the journal window remain in granular output, including
sessions excluded from the compatibility headline as implausible. Granular session and stage rows
preserve their original source instants, nanoseconds, identities and nullable source offsets. Local
clock fields are projections in the operation's captured export zone.

Canonical raw Health Connect records continue to use their independent raw-record ownership and
fidelity contract. Consumers reconstructing source events must use raw/detailed records rather than
inferring them from the compatibility headline.

## Schema decision

This is conformance to the already-documented noon-to-noon sleep ownership and existing sleep keys.
It changes no public key, JSON type, unit, CSV label/header, Markdown label or Bases frontmatter key.
The frozen `ios-v4` and shipped `android-analytical-v5` profile versions therefore do not change,
and their signature fixtures must not be rewritten. A future public shape or semantic contract
change still requires a new explicit profile/version under the existing guardrail.

## Verification and device QA

Pure JVM tests cover the issue reproduction, a tiny midnight-crossing fragment versus a
disconnected seven-hour sleep, first-day lookback, naps, split and overlapping sessions, duplicate
fragments, stage-less records, exact-noon ownership, invalid intervals, spring/fall DST, differing
source offsets, deterministic ordering and single/range parity. Existing
Markdown/Bases, JSON, CSV and schema-signature contract tests remain the exporter gate.

Physical Health Connect QA remains a release smoke test: on the Pixel 7, import or sync an overnight
session plus a nested short fragment, export the owning journal date as both one day and a range,
and compare the headline and detailed records. Device QA is not required by the deterministic JVM
suite.
