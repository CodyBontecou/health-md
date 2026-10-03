---
title: "The Health.md CLI connects your terminal — and your agents — directly to your phone."
description: "The standalone healthmd CLI and MCP server pair directly with iPhone or Android over your own network, without a Mac app, Health.md cloud, or account."
lead: "healthmd runs on macOS, Linux, or Windows and gives your shell, Codex, or Claude an explicit path to user-authorized health data on an open phone."
date: "2026-08-06T09:00:00.000Z"
updated: "2026-09-22T12:00:00.000Z"
category: "Product update"
draft: false
tags:
  - healthmd
  - cli
  - mcp
  - agents
---

Health.md started with a simple boundary: read health data on the phone, then put the result in files the user controls. The standalone **`healthmd` CLI** extends that boundary to macOS, Linux, and Windows without routing through the Health.md Mac app or a Health.md cloud service.

The paired app performs each Apple Health or Health Connect read. The CLI receives authenticated, encrypted, validated results over Manual IP or Tailscale.

## Pair once

```bash
healthmd direct pair
```

The current universal flow displays a QR code and a high-entropy pairing code. Open **Health.md → Direct CLI Access** on iPhone or Android, scan or enter the handoff, verify the computer, and keep the app open while new work begins. Reconnect trust is stored in the operating system credential service.

Then start small:

```bash
healthmd status
healthmd export --yesterday --raw --output yesterday.json
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"
```

An iPhone source also supports canonical extraction and typed queries:

```bash
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

Android preserves provider-native Health Connect snapshots rather than pretending they are HealthKit documents.

## Durable rather than disposable

A terminal timeout or network drop does not silently turn accepted work into failure. Direct exports are seven-day durable jobs:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Resume retains the immutable source, dates, scope, destination, request fingerprint, and committed partition frontier. Cancellation becomes terminal only after the phone acknowledges it.

## Connect an agent

For Codex:

```bash
healthmd setup codex
```

For Claude or another local MCP host, configure the absolute `healthmd` executable with arguments `mcp serve`. Call `healthmd_doctor` first, list metric IDs, and request an exact date and metric scope.

The published `0.1.0-alpha.7` portable preview exposes 19 tools. Current development source adds two approval-gated full-corpus raw-artifact tools for a total of 21; those tools are not a released alpha.7 promise. The `serve-read-only` entry remains limited to 13 readiness and typed-query tools.

## What stays private

- The phone performs platform health reads.
- There is no Health.md health-data cloud hop or account.
- Pairing and transport are authenticated and encrypted.
- Query requests carry explicit dates, metrics, sources, and detail.
- Large raw bodies go to validated files or a private durable spool, not automatically into a model conversation.
- Coverage, partial outcomes, missing dates, and unsupported types stay visible.

This is factual data access, not medical advice. Agents should preserve units, evidence, missingness, and limitations rather than diagnosing or calling a direction better or worse.

## Preview status

The portable package remains an explicitly unqualified preview. Use the exact `healthmd-cli/v<version>` release and matching mobile build named by release evidence. Do not use the repository-wide `/releases/latest` pointer; it remains reserved for Apple app releases.

Install the published preview on macOS or Linux:

```bash
brew install CodyBontecou/tap/healthmd
healthmd --version
```

Windows archives and the PowerShell installer are published per version. Verify the release checksums and signatures before running downloaded binaries.

<div class="cta-row">
<a class="button" href="/docs/cli/">Read the CLI docs</a>
<a class="button secondary" href="/docs/guides/connect-agent/">Connect an agent</a>
<a class="button secondary" href="/docs/release-status/">Check release status</a>
</div>
