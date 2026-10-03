---
title: "Why multi-day health exports should be resumable."
description: "Health.md direct exports use seven-day durable jobs, immutable requests, committed transfer frontiers, and acknowledged cancellation."
lead: "A terminal timeout is not proof that the phone stopped. Durable jobs make unknown outcomes inspectable instead of encouraging duplicate work."
date: "2026-09-22T14:10:00.000Z"
updated: "2026-09-22T14:10:00.000Z"
category: "Engineering"
draft: false
tags:
  - healthmd
  - cli
  - reliability
  - exports
---

A long health export crosses several unreliable boundaries. A phone can lock, Wi-Fi can change, a terminal can close, or a client deadline can expire after the phone already accepted the work.

Treating every disconnect as failure creates a dangerous retry loop: start again, duplicate the source work, and hope that file writes happen to be idempotent. Health.md's direct CLI uses a durable-job model instead.

## Process lifetime is not job lifetime

When an iPhone or Android device accepts a supported direct export, it returns a stable job ID. The job can remain recoverable for seven days even if the initiating CLI process exits.

Start with an explicit output plan:

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

If the wait times out, keep the returned ID and inspect the same job:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

A timeout does **not** cancel accepted work.

## Freeze the request

Safe resume requires more than remembering a cursor. Health.md binds the durable job to immutable details such as:

- paired device and provider;
- resolved date and metric scope;
- settings policy and detail level;
- destination identity;
- request fingerprint;
- session and transfer manifests;
- committed partition and byte frontier.

Resume cannot reinterpret those fields. A file job cannot silently switch to a different root. A raw job cannot become a different metric request halfway through.

## Commit partitions, not assumptions

After a disconnect, uncommitted bytes may be sent again. Committed partitions are accepted only when their immutable descriptors and digests match. This lets the receiver continue without silently duplicating or rewriting already acknowledged work.

The status response exposes health-free progress: job and session IDs, lifecycle state, processed and total days, committed bytes and partitions, completion fraction, pause state, and fixed expiration. It should not need to print samples merely to say that transfer is 60 percent complete.

## Cancellation needs acknowledgement

Explicit cancellation is also durable:

```bash
healthmd cancel JOB_UUID
```

The CLI first records and sends the request. Cancellation becomes terminal only after the phone acknowledges it. If the phone is unavailable, the correct state is `cancellation_pending`, not a fabricated success.

Ctrl-C stops the local process. It should not claim that remote work is cancelled.

## Partial is a data state

A process exit code is not enough to establish completeness. Parse the structured response, missing dates, failed queries, warnings, and coverage.

`--allow-partial` changes whether a validated partial result is accepted as a successful process exit. It does not repair the missing data or remove the limitations from the response.

Typed query pagination is separate again: a fresh phone acquisition can finish while the result still has a `next_cursor`. Use `--all-pages` within its aggregate safety limits or page deliberately.

## The safe retry order

An agent, shell script, or scheduler should:

1. retain the structured error and job ID;
2. inspect local job status;
3. reconnect the same phone if required;
4. resume the existing job;
5. start over only after the previous outcome is terminal, expired, or explicitly abandoned.

That sequence turns an ambiguous network failure into an auditable operation—and keeps a 30-day export from becoming three overlapping 30-day exports.

<div class="cta-row">
<a class="button" href="/docs/cli-jobs/">Read the durable-jobs guide</a>
<a class="button secondary" href="/docs/cli-direct/">Set up direct access</a>
</div>
