---
title: "Apple Health and Health Connect are not the same data model."
description: "How Health.md shares proven semantics across HealthKit and Health Connect without renaming related-but-different records into false parity."
lead: "Cross-platform health exports need common outcomes, explicit platform differences, and source-faithful archives—not a lowest-common-denominator fiction."
date: "2026-09-22T13:40:00.000Z"
updated: "2026-09-22T13:40:00.000Z"
category: "Engineering"
draft: false
tags:
  - healthmd
  - healthkit
  - health-connect
  - interoperability
  - schemas
---

Apple Health and Android Health Connect both store health and fitness information. That does not make every quantity, record type, permission, source field, or aggregation interchangeable.

A cross-platform exporter has two bad shortcuts available. It can expose completely different products with no shared contract, or it can force unlike records into one vocabulary and quietly lose meaning. Health.md takes a third path: unify the user outcome where semantics match, and preserve an explicit platform distinction where they do not.

## What can be shared

Many workflows have a genuinely common outcome:

- select a metric;
- choose local dates;
- preview an export;
- write Markdown, Bases, JSON, or CSV;
- preserve unit and source information;
- report permission, unsupported, empty, partial, and failed states;
- automate against a stable profile.

For proven equivalents, Health.md uses shared semantic IDs and canonical units. Daily boundaries are computed in the relevant local timezone. Sleep sessions use a shared start-date attribution rule.

## What must remain distinct

The platform APIs have different type systems and metadata. A HealthKit quantity, correlation, workout, clinical record, or series is not automatically equivalent to the nearest Health Connect record. Sources expose different fields, identifiers, deletion behavior, route access, permissions, and SDK-version boundaries.

That means a related statistic may need a platform-specific identity. Unsupported data is reported as unavailable instead of manufactured. A common export should never imply that Android supplied an Apple-only field or that an iPhone exposed a Health Connect-native structure.

## Summaries and archives solve different problems

A readable daily summary intentionally normalizes selected facts. It is useful for notes, charts, and ordinary automation.

An archival artifact should be more source-faithful. Apple lossless output preserves public schema-v8 daily documents with canonical HealthKit records. Android Raw API Snapshot preserves the fields exposed by the pinned Health Connect API and records a per-type manifest. Neither artifact claims to be a private provider-database backup.

This distinction is why Health.md does not convert an Android raw snapshot into a fake HealthKit document merely to give both files the same shape.

## Missing is not zero

Cross-platform software must retain capture state. These statements are not equivalent:

- the query completed and returned no records;
- permission was not granted;
- the installed OS lacks the type;
- the app does not support the type;
- the source failed or returned partial data.

Flattening those states into `0` creates confident but incorrect analysis. Health.md contracts keep missingness and limitations next to values so consumers can make defensible claims.

## A practical rule for consumers

Build against shared IDs only when the registry marks the mapping as exact. Otherwise, branch on the provider or omit the unsupported field. Always retain schema version, unit, timezone, source, coverage, and limitations.

Interoperability is not achieved by making two JSON objects look similar. It is achieved when both producers and consumers agree on what each field means—and when they can say precisely what was unavailable.

<div class="cta-row">
<a class="button" href="/docs/shared-metric-registry/">Browse the metric registry</a>
<a class="button secondary" href="/docs/guides/raw-snapshots/">Read about raw snapshots</a>
</div>
