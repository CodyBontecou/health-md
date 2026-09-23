---
title: "Full public and authorized corpus"
description: "Use the CLI to export every public type supported by a paired iPhone or Android source and authorized by the user."
---

<div class="availability preview"><strong>Development preview · not in alpha.7</strong><p>Do not automate this feature until a later <code>healthmd-cli/v&lt;version&gt;</code> release publishes it explicitly.</p></div>

`--full-corpus` requests every type exposed by the public API, supported by the installed build, and authorized by the user. It cannot read a private Apple, Google, or provider database.

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Apple preserves v8 documents and canonical HealthKit records. Android preserves the provider-native Health Connect snapshot. Inspect `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial`, and `read_error`. Omission is not proof of empty data.

Jobs remain resumable for seven days:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

A timeout does not cancel accepted work. Keep the corpus in a private file: it can contain exact times, routes, clinical text, medications, or attachments. The two current MCP corpus tools belong only to the complete local stdio profile.

<div class="related"><a href="/docs/cli-jobs/"><span>Recovery</span>Resume without duplicating work.</a><a href="/docs/guides/raw-snapshots/"><span>Android</span>Understand provider-native snapshots.</a></div>
