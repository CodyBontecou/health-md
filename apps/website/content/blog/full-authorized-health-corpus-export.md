---
title: "Export the full public, authorized health corpus from a paired phone."
description: "A release-post draft for Health.md CLI full-corpus export across public Apple Health and Health Connect APIs."
lead: "Full-corpus export is designed to preserve every public type that the installed mobile build supports and the user authorizes—without pretending it is a private database backup."
date: "2026-09-22T13:10:00.000Z"
updated: "2026-09-22T13:10:00.000Z"
category: "Product update"
draft: true
tags:
  - healthmd
  - cli
  - apple-health
  - health-connect
  - archive
---

> **Publication hold:** this capability exists in current development source but is not part of the published `0.1.0-alpha.7` CLI preview. Publish this post only after a later `healthmd-cli/v<version>` release names the mobile compatibility matrix and retained QA evidence.

A selected-metric export is usually the right answer. It is smaller, easier to inspect, and safer to share. Migration, archival, and interoperability work sometimes needs a different operation: ask the paired phone for every public record type it can actually expose.

That is what Health.md's full-corpus mode is designed to do.

```bash
healthmd export --all --raw --full-corpus \
  --output apple-health-corpus.json

healthmd export --all --raw --full-corpus \
  --provider health_connect \
  --raw-format ndjson \
  --output health-connect-corpus.ndjson
```

## “Full” has a precise boundary

Full-corpus does **not** mean a forensic copy of Apple's, Google's, or a provider's private database. It means the intersection of:

1. types exposed by the platform's public API;
2. types supported by the installed Health.md mobile build; and
3. types the user authorized Health.md to read.

An omitted record is therefore not proof that the event never happened. The export records outcomes such as `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial`, and `read_error` so a consumer can distinguish known-empty from unknown.

## Preserve the source model

On iPhone, the artifact preserves public schema-v8 daily documents and canonical HealthKit source records. On Android, it preserves a provider-native Health Connect snapshot. Health.md does not rename a related Android statistic into an Apple identity simply to make two archives look alike.

That distinction is important for future migrations. A normalized summary is convenient for a chart; a source-faithful archive must retain identity, timestamps, units, provenance, and limitations.

## Resume instead of starting over

Large transfers are seven-day durable jobs. A terminal timeout does not cancel accepted work:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

The phone and CLI bind the immutable request, source, scope, and committed transfer frontier. Resume continues the same operation instead of silently creating a second one.

## Keep the artifact private

A corpus can contain exact times, routes, clinical text, medications, symptoms, and attachments. Write it to a private path, verify checksums or receipts where provided, and do not paste it into a model conversation.

Current development MCP source also contains two approval-gated corpus tools, but they belong only to the complete local stdio profile. Release documentation must continue to separate those tools from the 19-tool alpha.7 package.

<div class="cta-row">
<a class="button" href="/docs/full-corpus-export/">Read the preview guide</a>
<a class="button secondary" href="/docs/release-status/">Check release status</a>
</div>
