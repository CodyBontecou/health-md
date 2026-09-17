---
title: "healthmd resume"
description: "Resume the exact immutable request bound to an interrupted durable job."
---

Resume an interrupted durable export or extraction job without changing its phone, dates, selection, destination, or artifact type.

## Synopsis

```text
healthmd resume <JOB_UUID> [OPTIONS]
```

Omit the job UUID to receive local guidance without contacting a phone.

## Options

| Argument or option | Description | Default |
|---|---|---|
| `<JOB_UUID>` | Durable job UUID from an export receipt or `healthmd status --job`. | Required to execute. |
| `--output <PATH>` | Atomically write a resumed raw or extract artifact. | Original behavior or stdout, according to job type. |
| `--format <json\|jsonl>` | Select output encoding when the immutable job type permits it. | Job-specific. |
| `--allow-partial` | Accept a validated partial result with a successful exit status. | Off |
| `--timeout <SECONDS>` | Wait for resumed work. Range: 5–900. | `300` |
| `--wake-timeout <SECONDS>` | Wait for the paired phone to become active. | `120` |
| `--no-wake` | Skip the best-effort notification nudge. | Off |

This command also accepts all [global options](/docs/cli-reference/#global-options).

## Examples

```bash
# Inspect the saved job first; this is local-only.
healthmd status --job 11111111-2222-4333-8444-555555555555

# Resume it.
healthmd resume 11111111-2222-4333-8444-555555555555

# Commit a resumed artifact to a new output path when permitted.
healthmd resume 11111111-2222-4333-8444-555555555555 \
  --output resumed.json
```

## Safety

Resume verifies the saved peer, request fingerprint, date scope, destination identity, manifests, partition chain, and committed frontier. A mismatch fails closed.

Timeout, Ctrl-C, process death, disconnection, and mobile background expiration pause work; they do not cancel the phone-side job. Use [`healthmd cancel`](/docs/cli-reference/cancel/) only when cancellation is intended.
