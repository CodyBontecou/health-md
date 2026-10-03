---
title: "healthmd cancel"
description: "Request explicit cancellation of one durable direct job."
---

Ask the authenticated mobile source to cancel one durable job.

## Synopsis

```text
healthmd cancel <JOB_UUID> [OPTIONS]
```

Omit the job UUID to receive local guidance without contacting a phone.

## Options

| Argument or option | Description | Default |
|---|---|---|
| `<JOB_UUID>` | Durable job UUID from an export receipt or status result. | Required to execute. |
| `--wake-timeout <SECONDS>` | Wait for the paired phone to become active. | `120` |
| `--no-wake` | Skip the best-effort notification nudge. | Off |

This command also accepts all [global options](/docs/cli-reference/#global-options).

## Example

```bash
healthmd cancel 11111111-2222-4333-8444-555555555555
healthmd status --job 11111111-2222-4333-8444-555555555555
```

## Acknowledgement

Cancellation becomes terminal only after acknowledgement from the authenticated phone. A local timeout, Ctrl-C, process exit, disconnection, or cancellation request by itself is not terminal cancellation.

Keep Health.md open on the phone and use `healthmd status --job` to distinguish `cancellation_pending` from a terminal cancelled state.
