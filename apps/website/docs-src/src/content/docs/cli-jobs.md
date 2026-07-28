---
title: "Durable CLI jobs and automation"
description: "Automate healthmd safely with machine-readable output, bounded waits, seven-day durable jobs, explicit partial states, resume, and acknowledged cancellation."
---

Health.md treats connected export and context-acquisition work as durable jobs. The job lifetime is separate from the process that started it. A terminal can close or a network connection can fail without discarding completed partitions.

This page applies to file export, strict raw export, canonical extraction, and fresh encrypted-context acquisition unless a command documents a narrower rule.

## The central rule

A timeout or disconnect does not mean cancellation.

Do not start a duplicate after an unknown outcome. Save the returned job ID, inspect its state, and resume the same job.

Export, raw, and extraction jobs use the top-level lifecycle commands:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Encrypted-context acquisition jobs use the local agent lifecycle:

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## Seven-day lifetime

A durable job has a fixed `expires_at` seven days after creation. Progress does not extend it. Both peers persist the immutable request and enough committed transfer state to resume safely.

A job can persist:

- exact dates or resolved all-history identifiers;
- metric, category, source, and detail scope;
- backend and paired-device binding;
- settings policy;
- raw profile or extraction selection;
- file destination identity;
- request fingerprint;
- session and transfer manifests;
- partition digest chain;
- committed partition and byte frontier;
- completion or cancellation acknowledgement.

Resume cannot reinterpret any of these fields.

## State is not just running or finished

A job response may include:

| Field | Meaning |
|---|---|
| `durable` | Whether the operation has recoverable job state |
| `state` | Current durable lifecycle state |
| `job_id` | Stable job identifier |
| `session_id` | Bound transfer session identifier |
| `paused` | Whether work needs the same iPhone to reconnect |
| `processed_days` / `total_days` | Logical owner-day progress |
| `committed_partitions` | Partitions durably acknowledged by the receiver |
| `committed_bytes` | Payload bytes safely committed |
| `fraction_complete` | Health-free progress fraction |
| `expires_at` | Fixed job expiration timestamp |

Status fields contain dates, IDs, counts, bytes, and safe errors. They should not contain health samples.

## Start a job with an explicit output plan

Raw export:

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

Canonical extraction:

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

Direct generated files:

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

Pick the final output or destination before the request starts. A raw job binds its output behavior. A direct file job binds the exact destination root into the immutable request.

## Resume

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

For direct mode, select the same backend, device, transport, port, and iPhone used by the original request:

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

Pending bytes may be discarded after a disconnect. Committed partitions are not retransmitted or reinterpreted. The receiver accepts an already committed partition only when every immutable descriptor matches.

A file job does not accept a replacement destination during resume. If the original root changed, Health.md fails closed rather than writing into a different folder.

## Cancel

Use the lifecycle that created the job:

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

Cancellation has two stages:

1. the CLI records and sends a durable cancellation request;
2. the iPhone acknowledges cancellation and makes it terminal.

If the iPhone is unavailable, the job remains `cancellation_pending`. Reopen the same iPhone and retry cancel. Do not report a job as cancelled based only on local intent.

A process receiving Ctrl-C should exit without fabricating terminal cancellation. Use the explicit cancel command when cancellation is intended.

## Output channels

Health.md separates command results from progress:

| Channel | Content |
|---|---|
| stdout | Versioned JSON command result, error, or requested JSON/JSONL stream |
| stderr | Plain pairing instructions, health-free progress, JSONL receipt when streaming, and usage text |
| `--output PATH` | Atomically committed health-bearing JSON or JSONL |
| `OUTPUT.receipt.json` | Health-free extraction receipt for JSONL file output |

`--help` is plain text. Argument failures before execution use stderr and exit 2. Once a command executes, runtime failures use machine-readable JSON.

Do not merge stdout and stderr in an automation parser.

## Exit status and data status

Process exit status is only one signal. Parse the response before claiming success.

| Result | Default exit behavior |
|---|---|
| Complete success | Zero |
| Complete-empty requested scope | Zero |
| Validated partial strict raw or extraction | Nonzero |
| Partial with explicit `--allow-partial` | Zero, but response stays partial |
| Argument error | Exit 2, plain text on stderr |
| Validation or transport failure | Nonzero with structured runtime error |

`--allow-partial` is acceptance policy, not data repair. Every missing day, failed query, unsupported type, and warning remains visible.

## Page traversal is separate from job completion

Typed query responses are paged. A fresh acquisition job can complete while the query still has another page.

Without `--all-pages`, inspect `next_cursor`. When a next page exists, the high-level CLI reports `partial_success` rather than claiming full traversal.

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages` follows opaque cursors, checks for repeats, and enforces an aggregate page and byte ceiling. If the ceiling is reached, narrow the scope or use the low-level API to page manually. There is no hidden total-result cap, but one invocation remains bounded.

## Fresh, cached, and reused coverage

High-level query commands acquire fresh iPhone data by default:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Use cached data only when stale context is acceptable:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Use `--reuse-covered` to skip acquisition only after Health.md verifies complete metric-aware summary coverage for the requested days:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

The reuse shortcut does not apply to lossless data or newly projected sleep-session operations. It never treats a different provider or an older stale blob as proof of this request's fresh completion.

## Shell example

This example keeps the health payload in a protected file and prints only safe status fields. It assumes GNU `timeout` is installed. Other automation hosts should apply their own process deadline.

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

Do not enable `set -x` around a command that may stream health JSON or include sensitive paths.

## Agent behavior after an unknown outcome

An agent or scheduler should follow this order:

1. Read the structured error and job ID.
2. Run `status --job` locally.
3. Check whether the job is paused, terminal, expired, or awaiting acknowledgement.
4. Reopen the same iPhone when fresh work or acknowledgement is needed.
5. Resume the existing job with the same backend and device.
6. Start a new job only after the prior outcome is known or expiration is explicitly accepted.

Retrying a mutation blindly can duplicate source work even when file commits themselves are idempotent.

## Common machine-readable errors

| Code | Meaning | Safe response |
|---|---|---|
| `timed_out` | The command stopped waiting before the job finished | Inspect the returned job and resume it |
| `job_not_found` | No local durable record exists for that ID | Confirm backend and state directory before starting over |
| `job_expired` | The fixed seven-day deadline elapsed | Record the gap and create a new request if appropriate |
| `direct_export_paused` | Direct work needs the paired iPhone again | Reopen iPhone and resume |
| `direct_cancellation_pending` | Local cancel intent lacks iPhone acknowledgement | Reopen iPhone and retry cancel |
| `invalid_direct_raw_response` | Strict raw validation failed | Do not consume the output |
| `invalid_direct_file_receipt` | File manifest or commit receipt failed validation | Do not repair or append files manually |
| `partial_canonical_extraction` | Requested extraction is incomplete | Inspect receipt; opt into partial only when accepted |
| `unvalidated_response_too_large` | One result cannot be exposed under current validation bounds | Narrow scope or use an appropriate output mode |
| `stale_cursor` | Encrypted context changed after the page cursor was issued | Restart that query against the current corpus |

## Progress without payload logging

Use `--progress-json` for high-level query phases and page traversal:

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

Progress JSONL can include phase, page count, item count, dates, and safe diagnostics. It must not include health values. Keep it separate from the final result and apply an appropriate retention policy anyway.

## Related

<div class="related">
  <a href="/docs/cli/"><span>Setup</span>Health.md CLI: install, choose a backend, and understand command output.</a>
  <a href="/docs/cli-direct/"><span>Direct</span>Direct iPhone CLI: pairing, finite background time, explicit destination, and trusted resume.</a>
  <a href="/docs/agent-queries/"><span>Paging</span>Typed query cookbook: fresh and cached modes, page traversal, coverage, and receipts.</a>
  <a href="/docs/reference/generated/cli/exit-codes/"><span>Generated contract</span>CLI exit codes: production-generated status and error behavior.</a>
</div>
