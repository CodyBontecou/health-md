---
title: "healthmd status"
description: "Check live mobile readiness or inspect one locally stored durable job."
---

Check the paired phone's live readiness, or read one durable job from local storage.

## Synopsis

```text
healthmd status [--job <JOB_UUID>]
```

Without `--job`, the command contacts the selected paired phone. With `--job`, it reads local state and does not contact a phone.

## Options

| Option | Description |
|---|---|
| `--job <JOB_UUID>` | Read one durable job instead of checking live readiness. |

This command also accepts all [global options](/docs/cli-reference/#global-options).

## Examples

Check the only paired phone:

```bash
healthmd status
```

Select a phone when more than one is paired:

```bash
healthmd status --device 11111111-2222-4333-8444-555555555555
```

Inspect a durable job without contacting the phone:

```bash
healthmd status --job 11111111-2222-4333-8444-555555555555
```

## Result

Live status reports the selected device, direct connectivity, source readiness, and wake availability without including health values. Job status reports the saved request state, progress, and whether it can be resumed or still awaits cancellation acknowledgement.

## Related commands

- [`healthmd direct devices`](/docs/cli-reference/direct/#healthmd-direct-devices) lists paired phones.
- [`healthmd resume`](/docs/cli-reference/resume/) continues an interrupted job.
- [`healthmd cancel`](/docs/cli-reference/cancel/) requests explicit cancellation.
